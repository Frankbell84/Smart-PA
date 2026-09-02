import Foundation

enum CloudManifestEntryRoleV1: UInt8, Sendable {
    case localManifest = 1
    case encryptedOriginal = 2
    case encryptedThumbnail = 3
}

/// The build-11 photo store is already encrypted with its independent local
/// vault key. Cloud recovery must preserve that key without exposing it to the
/// provider. This value lives only inside the CVK-encrypted cloud manifest.
struct CloudLocalVaultSecretV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x4c, 0x56, 0x4b, 0x31, 0x00])
    static let encodedByteCount = 52

    let localVaultKey: Data
    let sourceVaultCreatedAtMilliseconds: UInt64

    func encoded() throws -> Data {
        guard localVaultKey.count == CloudSecretKeyV1.byteCount else {
            throw CloudProtocolError.invalidLength("local vault key")
        }
        guard sourceVaultCreatedAtMilliseconds > 0 else {
            throw CloudProtocolError.invalidValue("source vault creation time")
        }
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "local vault secret magic")
        encoder.append(CloudProtocolSuite.version)
        try encoder.append(
            fixed: localVaultKey,
            byteCount: CloudSecretKeyV1.byteCount,
            field: "local vault key"
        )
        encoder.append(sourceVaultCreatedAtMilliseconds)
        return encoder.data
    }

    init(localVaultKey: Data, sourceVaultCreatedAtMilliseconds: UInt64) {
        self.localVaultKey = localVaultKey
        self.sourceVaultCreatedAtMilliseconds = sourceVaultCreatedAtMilliseconds
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data, maximumByteCount: Self.encodedByteCount)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        localVaultKey = try decoder.readFixedData(
            byteCount: CloudSecretKeyV1.byteCount,
            field: "local vault key"
        )
        sourceVaultCreatedAtMilliseconds = try decoder.readUInt64()
        try decoder.requireFinished()
        guard sourceVaultCreatedAtMilliseconds > 0 else {
            throw CloudProtocolError.invalidValue("source vault creation time")
        }
    }
}

struct CloudManifestParentV1: Equatable, Sendable {
    let generation: UInt64
    let manifestObjectID: UUID
    let storedObjectSHA256: Data

    func validate() throws {
        guard generation >= 1,
              !manifestObjectID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("manifest parent")
        }
        guard storedObjectSHA256.count == CloudProtocolLimits.sha256ByteCount else {
            throw CloudProtocolError.invalidLength("parent manifest digest")
        }
    }
}

struct CloudManifestEntryV1: Equatable, Sendable {
    let entryID: UUID
    let role: CloudManifestEntryRoleV1
    let localStorageName: String
    let cloudObjectID: UUID
    let cloudObjectVersion: UInt64
    let innerCiphertextByteCount: UInt64
    let innerCiphertextSHA256: Data
    let storedCloudObjectByteCount: UInt64
    let storedCloudObjectSHA256: Data
    let chunkCount: UInt32

    func validate() throws {
        guard !entryID.isCloudNilUUID,
              !cloudObjectID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("manifest entry identifier")
        }
        guard cloudObjectVersion >= 1 else {
            throw CloudProtocolError.invalidValue("cloud object version")
        }
        try Self.validateStorageName(localStorageName, role: role)
        guard innerCiphertextByteCount >= 28,
              innerCiphertextByteCount <= CloudProtocolLimits.innerObjectByteCount else {
            throw CloudProtocolError.invalidLength("inner ciphertext")
        }
        guard innerCiphertextSHA256.count == CloudProtocolLimits.sha256ByteCount,
              storedCloudObjectSHA256.count == CloudProtocolLimits.sha256ByteCount else {
            throw CloudProtocolError.invalidLength("object digest")
        }
        let expectedChunkCount = ((innerCiphertextByteCount - 1)
            / UInt64(CloudProtocolLimits.cloudObjectChunkByteCount)) + 1
        guard expectedChunkCount <= UInt64(UInt32.max),
              chunkCount == UInt32(expectedChunkCount) else {
            throw CloudProtocolError.invalidValue("manifest entry chunk count")
        }
        let expectedStoredByteCount = try CloudObjectHeaderV1.storedByteCount(
            plaintextByteCount: innerCiphertextByteCount,
            chunkCount: chunkCount
        )
        guard storedCloudObjectByteCount == expectedStoredByteCount else {
            throw CloudProtocolError.invalidLength("stored cloud object")
        }
    }

    private static func validateStorageName(
        _ name: String,
        role: CloudManifestEntryRoleV1
    ) throws {
        guard !name.isEmpty,
              name == name.precomposedStringWithCanonicalMapping,
              name.utf8.count <= CloudProtocolLimits.localStorageNameByteCount,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\0"),
              URL(fileURLWithPath: name).lastPathComponent == name else {
            throw CloudProtocolError.invalidValue("local storage name")
        }

        switch role {
        case .localManifest:
            guard name == "manifest.khm" else {
                throw CloudProtocolError.invalidValue("local manifest name")
            }
        case .encryptedOriginal:
            guard URL(fileURLWithPath: name).pathExtension.lowercased() == "khp" else {
                throw CloudProtocolError.invalidValue("encrypted original name")
            }
        case .encryptedThumbnail:
            guard URL(fileURLWithPath: name).pathExtension.lowercased() == "kht" else {
                throw CloudProtocolError.invalidValue("encrypted thumbnail name")
            }
        }
    }
}

struct CloudManifestV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x4d, 0x41, 0x4e, 0x31, 0x00])
    static let currentVersion: UInt32 = 1
    private static let minimumEncodedEntryByteCount = 130

    let accountID: UUID
    let vaultID: UUID
    let snapshotID: UUID
    let generation: UInt64
    let parent: CloudManifestParentV1?
    let createdAtMilliseconds: UInt64
    let localModelVersion: UInt32
    let localVaultSecret: CloudLocalVaultSecretV1
    let entries: [CloudManifestEntryV1]

    func validate() throws {
        guard !accountID.isCloudNilUUID,
              !vaultID.isCloudNilUUID,
              !snapshotID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("manifest identifier")
        }
        guard generation >= 1,
              createdAtMilliseconds > 0,
              localModelVersion == UInt32(VaultPhotoManifest.currentVersion) else {
            throw CloudProtocolError.invalidValue("manifest generation or model")
        }
        _ = try localVaultSecret.encoded()
        if generation == 1 {
            guard parent == nil else {
                throw CloudProtocolError.invalidValue("first-generation parent")
            }
        } else {
            guard let parent,
                  parent.generation == generation - 1 else {
                throw CloudProtocolError.invalidValue("manifest parent generation")
            }
            try parent.validate()
        }
        guard !entries.isEmpty,
              entries.count <= CloudProtocolLimits.manifestEntryCount,
              entries.first?.role == .localManifest else {
            throw CloudProtocolError.invalidValue("manifest entries")
        }

        var entryIDs = Set<UUID>()
        var objectIDs = Set<UUID>()
        var storageNames = Set<String>()
        var localManifestCount = 0
        var totalInnerByteCount: UInt64 = 0

        for entry in entries {
            try entry.validate()
            guard entryIDs.insert(entry.entryID).inserted else {
                throw CloudProtocolError.duplicateIdentifier("entry ID")
            }
            guard objectIDs.insert(entry.cloudObjectID).inserted else {
                throw CloudProtocolError.duplicateIdentifier("cloud object ID")
            }
            guard storageNames.insert(entry.localStorageName).inserted else {
                throw CloudProtocolError.duplicateIdentifier("local storage name")
            }
            if entry.role == .localManifest {
                localManifestCount += 1
            }
            let (newTotal, overflow) = totalInnerByteCount.addingReportingOverflow(
                entry.innerCiphertextByteCount
            )
            guard !overflow,
                  newTotal <= CloudProtocolLimits.generationInnerByteCount else {
                throw CloudProtocolError.invalidLength("generation ciphertext")
            }
            totalInnerByteCount = newTotal
        }

        guard localManifestCount == 1 else {
            throw CloudProtocolError.invalidValue("local manifest count")
        }
    }

    func encoded() throws -> Data {
        try validate()
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "manifest magic")
        encoder.append(Self.currentVersion)
        encoder.append(uuid: accountID)
        encoder.append(uuid: vaultID)
        encoder.append(uuid: snapshotID)
        encoder.append(generation)
        encoder.append(UInt8(parent == nil ? 0 : 1))
        if let parent {
            encoder.append(parent.generation)
            encoder.append(uuid: parent.manifestObjectID)
            try encoder.append(
                fixed: parent.storedObjectSHA256,
                byteCount: CloudProtocolLimits.sha256ByteCount,
                field: "parent manifest digest"
            )
        }
        encoder.append(createdAtMilliseconds)
        encoder.append(localModelVersion)
        try encoder.append(
            fixed: localVaultSecret.encoded(),
            byteCount: CloudLocalVaultSecretV1.encodedByteCount,
            field: "local vault secret"
        )
        encoder.append(UInt32(entries.count))

        for entry in entries {
            encoder.append(uuid: entry.entryID)
            encoder.append(entry.role.rawValue)
            try encoder.append(
                string: entry.localStorageName,
                maximumUTF8ByteCount: CloudProtocolLimits.localStorageNameByteCount,
                field: "local storage name"
            )
            encoder.append(uuid: entry.cloudObjectID)
            encoder.append(entry.cloudObjectVersion)
            encoder.append(entry.innerCiphertextByteCount)
            try encoder.append(
                fixed: entry.innerCiphertextSHA256,
                byteCount: CloudProtocolLimits.sha256ByteCount,
                field: "inner ciphertext digest"
            )
            encoder.append(entry.storedCloudObjectByteCount)
            try encoder.append(
                fixed: entry.storedCloudObjectSHA256,
                byteCount: CloudProtocolLimits.sha256ByteCount,
                field: "stored cloud-object digest"
            )
            encoder.append(entry.chunkCount)
        }

        guard encoder.data.count <= CloudProtocolLimits.manifestPlaintextByteCount else {
            throw CloudProtocolError.invalidLength("manifest plaintext")
        }
        return encoder.data
    }

    init(
        accountID: UUID,
        vaultID: UUID,
        snapshotID: UUID,
        generation: UInt64,
        parent: CloudManifestParentV1?,
        createdAtMilliseconds: UInt64,
        localModelVersion: UInt32 = UInt32(VaultPhotoManifest.currentVersion),
        localVaultSecret: CloudLocalVaultSecretV1,
        entries: [CloudManifestEntryV1]
    ) {
        self.accountID = accountID
        self.vaultID = vaultID
        self.snapshotID = snapshotID
        self.generation = generation
        self.parent = parent
        self.createdAtMilliseconds = createdAtMilliseconds
        self.localModelVersion = localModelVersion
        self.localVaultSecret = localVaultSecret
        self.entries = entries
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(
            data,
            maximumByteCount: CloudProtocolLimits.manifestPlaintextByteCount
        )
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == Self.currentVersion else {
            throw CloudProtocolError.unsupportedVersion
        }
        accountID = try decoder.readUUID()
        vaultID = try decoder.readUUID()
        snapshotID = try decoder.readUUID()
        generation = try decoder.readUInt64()

        let parentFlag = try decoder.readUInt8()
        switch parentFlag {
        case 0:
            parent = nil
        case 1:
            parent = CloudManifestParentV1(
                generation: try decoder.readUInt64(),
                manifestObjectID: try decoder.readUUID(),
                storedObjectSHA256: try decoder.readFixedData(
                    byteCount: CloudProtocolLimits.sha256ByteCount,
                    field: "parent manifest digest"
                )
            )
        default:
            throw CloudProtocolError.invalidValue("manifest parent flag")
        }

        createdAtMilliseconds = try decoder.readUInt64()
        localModelVersion = try decoder.readUInt32()
        localVaultSecret = try CloudLocalVaultSecretV1(
            decoding: decoder.readFixedData(
                byteCount: CloudLocalVaultSecretV1.encodedByteCount,
                field: "local vault secret"
            )
        )
        let entryCount = Int(try decoder.readUInt32())
        guard entryCount > 0,
              entryCount <= CloudProtocolLimits.manifestEntryCount,
              entryCount <= decoder.remainingByteCount / Self.minimumEncodedEntryByteCount else {
            throw CloudProtocolError.invalidLength("manifest entry count")
        }

        var decodedEntries: [CloudManifestEntryV1] = []
        decodedEntries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            let entryID = try decoder.readUUID()
            guard let role = CloudManifestEntryRoleV1(rawValue: try decoder.readUInt8()) else {
                throw CloudProtocolError.invalidValue("manifest entry role")
            }
            let localStorageName = try decoder.readString(
                maximumUTF8ByteCount: CloudProtocolLimits.localStorageNameByteCount,
                field: "local storage name"
            )
            decodedEntries.append(
                CloudManifestEntryV1(
                    entryID: entryID,
                    role: role,
                    localStorageName: localStorageName,
                    cloudObjectID: try decoder.readUUID(),
                    cloudObjectVersion: try decoder.readUInt64(),
                    innerCiphertextByteCount: try decoder.readUInt64(),
                    innerCiphertextSHA256: try decoder.readFixedData(
                        byteCount: CloudProtocolLimits.sha256ByteCount,
                        field: "inner ciphertext digest"
                    ),
                    storedCloudObjectByteCount: try decoder.readUInt64(),
                    storedCloudObjectSHA256: try decoder.readFixedData(
                        byteCount: CloudProtocolLimits.sha256ByteCount,
                        field: "stored cloud-object digest"
                    ),
                    chunkCount: try decoder.readUInt32()
                )
            )
        }
        entries = decodedEntries
        try decoder.requireFinished()
        try validate()
    }
}
