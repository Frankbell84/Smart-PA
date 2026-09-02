import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class CloudProtocolTests: XCTestCase {
    func testGeneratedCloudSecretKeysAre256BitAndDoNotRepeat() {
        var observed = Set<Data>()
        for _ in 0..<1_000 {
            let key = CloudSecretKeyV1.generate()
            XCTAssertEqual(key.count, 32)
            XCTAssertTrue(observed.insert(key).inserted)
        }
    }

    func testCloudRecoveryCodeVectorAndKeyMaterialAreCanonical() throws {
        let value = try CloudRecoveryCodeV1.value(rawBytes: Data(0x00...0x13))

        XCTAssertEqual(
            value.formatted,
            "KH1-000G-40R4-0M30-E209-185G-R38E-1W81-24GK-DN"
        )
        XCTAssertEqual(
            try CloudRecoveryCodeV1.decode(value.formatted),
            value
        )
        XCTAssertEqual(
            try CloudRecoveryCodeV1.keyMaterial(from: value.formatted),
            try Data(cloudHex: """
            6b6579686f6c6c6f772e636c6f75642d7265636f766572792d6b65792e7631
            3a3030304734305234304d3330453230393138354752333845315738313234474b
            """)
        )
        XCTAssertEqual(
            try CloudRecoveryCodeV1.decode(
                "kh1-O00G-40R4-0M30-E209-L85G-R38E-1W8L-24GK-DN"
            ),
            value
        )
    }

    func testCloudRecoveryCodeRejectsWrongVersionAndChecksum() throws {
        let valid = "KH1-000G-40R4-0M30-E209-185G-R38E-1W81-24GK-DN"
        XCTAssertThrowsError(
            try CloudRecoveryCodeV1.decode(valid.replacingOccurrences(of: "KH1", with: "KH2"))
        )
        XCTAssertThrowsError(
            try CloudRecoveryCodeV1.decode(String(valid.dropLast()) + "0")
        ) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidValue("cloud recovery code checksum")
            )
        }
    }

    func testGeneratedCloudRecoveryCodesDoNotRepeat() throws {
        var observed = Set<String>()
        for _ in 0..<1_000 {
            let code = try CloudRecoveryCodeV1.generate()
            XCTAssertTrue(observed.insert(code).inserted)
            XCTAssertEqual(try CloudRecoveryCodeV1.decode(code).formatted, code)
        }
    }

    func testRecoveryWrappingKeyAndEnvelopeCiphertextVector() throws {
        let recoveryCode = "KH1-000G-40R4-0M30-E209-185G-R38E-1W81-24GK-DN"
        let header = CloudRecoveryEnvelopeHeaderV1(
            accountKeyID: fixtureAccountID,
            envelopeGeneration: 7,
            kdfSalt: Data(0x00...0x0f)
        )
        let key = try CloudKeyDerivationV1.recoveryWrappingKey(
            recoveryCode: recoveryCode,
            header: header
        )
        XCTAssertEqual(
            key.cloudData,
            try Data(cloudHex: "294f2a4dd45c12989e92826390f8fba4cf942a6d6d22af98d1886abc7468adbd")
        )

        let secret = CloudAccountMasterKeySecretV1(
            accountMasterKey: Data(0x40...0x5f),
            createdAtMilliseconds: 1_720_000_000_123,
            generation: 2
        )
        let container = try CloudRecoveryEnvelopeV1.sealForTesting(
            secret,
            recoveryCode: recoveryCode,
            header: header,
            keyDeriver: FixtureCloudRecoveryKeyDeriver(key: key.cloudData),
            nonce: Data(0x00...0x0b)
        )
        XCTAssertEqual(
            container,
            try Data(cloudHex: """
            4b4843524543310001000000010000000100000000112233445566778899aabb
            ccddeeff0700000000000000000102030405060708090a0b0c0d0e0f58000000
            000102030405060708090a0b9c00af664a0f4d4466843e6483743f36d284adbd
            691bacd89ba722a78f9b33ae6a276438362aabbd371409f320477808746e0ef8
            b40aae5a98e69cdfca5945e6535207be3a3949250d9c7804
            """)
        )
        let opened = try CloudRecoveryEnvelopeV1.open(
            container,
            recoveryCode: recoveryCode,
            keyDeriver: FixtureCloudRecoveryKeyDeriver(key: key.cloudData)
        )
        XCTAssertEqual(opened.header, header)
        XCTAssertEqual(opened.secret, secret)

        XCTAssertThrowsError(
            try CloudRecoveryEnvelopeV1.open(
                container,
                recoveryCode: recoveryCode,
                keyDeriver: FixtureCloudRecoveryKeyDeriver(
                    key: Data(repeating: 0xff, count: 32)
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudProtocolError, .authenticationFailed)
        }
    }

    func testVaultWrappingKeyAndEnvelopeCiphertextVector() throws {
        let accountMasterKey = Data(0x40...0x5f)
        let header = CloudVaultKeyEnvelopeHeaderV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            vaultKeyID: fixtureObjectID,
            accountKeyGeneration: 3
        )
        XCTAssertEqual(
            try CloudKeyDerivationV1.vaultWrappingKey(
                accountMasterKey: accountMasterKey,
                header: header
            ).cloudData,
            try Data(cloudHex: "94e8084a011e9a2193735ba548f6ec997fb3b08e6e065e10e9d3fd4f1e539f94")
        )

        let secret = CloudVaultKeySecretV1(
            cloudVaultKey: Data(0x60...0x7f),
            createdAtMilliseconds: 1_720_000_000_123,
            generation: 4
        )
        let container = try CloudVaultKeyEnvelopeV1.sealForTesting(
            secret,
            accountMasterKey: accountMasterKey,
            header: header,
            nonce: Data(0x0c...0x17)
        )
        XCTAssertEqual(
            container,
            try Data(cloudHex: """
            4b4843564b455900010000000100000000112233445566778899aabbccddeeff
            ffeeddccbbaa99887766554433221100aaaaaaaabbbbccccddddeeeeeeeeeeee03
            00000000000000580000000c0d0e0f10111213141516170bcdc1bcea37fdc1de
            7dd568b314de318530ca3b01df0cb1977009bbf2c2fe529ab9dccba38ca54838e
            aba125106af1a6c1738a8f441a8d25efffe3bc6a46c058c8a9d0db5f82df55b
            d98805
            """)
        )
        let opened = try CloudVaultKeyEnvelopeV1.open(
            container,
            accountMasterKey: accountMasterKey
        )
        XCTAssertEqual(opened.header, header)
        XCTAssertEqual(opened.secret, secret)
        XCTAssertThrowsError(
            try CloudVaultKeyEnvelopeV1.open(
                container,
                accountMasterKey: Data(repeating: 0xff, count: 32)
            )
        ) { error in
            XCTAssertEqual(error as? CloudProtocolError, .authenticationFailed)
        }
    }

    func testCloudObjectChunkKeyCiphertextAndContextBindingVector() throws {
        let cloudVaultKey = Data(0x60...0x7f)
        let header = CloudObjectHeaderV1(
            purpose: .content,
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            objectID: fixtureObjectID,
            objectVersion: 4,
            plaintextByteCount: 32,
            chunkCount: 1
        )
        XCTAssertEqual(
            try CloudKeyDerivationV1.objectChunkKey(
                cloudVaultKey: cloudVaultKey,
                header: header,
                sequence: 0
            ).cloudData,
            try Data(cloudHex: "570b11cf7273923ef782de722c2e0f66f4e205896f0a99fd5e2d636232624b55")
        )

        let frame = try CloudObjectChunkV1.sealForTesting(
            Data(0x00...0x1f),
            cloudVaultKey: cloudVaultKey,
            header: header,
            sequence: 0,
            isFinal: true,
            nonce: Data(0x18...0x23)
        )
        XCTAssertEqual(
            frame,
            try Data(cloudHex: """
            0000000001200000003c00000018191a1b1c1d1e1f202122235fd8ccfd9c25c2
            87df23ad1daf43b765621f56949c40495c4dfa9c82c25abcd7176125b93ebd2fe
            2f99594efed45c53a
            """)
        )
        let opened = try CloudObjectChunkV1.open(
            frame,
            cloudVaultKey: cloudVaultKey,
            header: header
        )
        XCTAssertEqual(opened.sequence, 0)
        XCTAssertTrue(opened.isFinal)
        XCTAssertEqual(opened.plaintext, Data(0x00...0x1f))

        let otherVaultHeader = CloudObjectHeaderV1(
            purpose: .content,
            accountID: fixtureAccountID,
            vaultID: UUID(uuidString: "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb")!,
            objectID: fixtureObjectID,
            objectVersion: 4,
            plaintextByteCount: 32,
            chunkCount: 1
        )
        XCTAssertThrowsError(
            try CloudObjectChunkV1.open(
                frame,
                cloudVaultKey: cloudVaultKey,
                header: otherVaultHeader
            )
        ) { error in
            XCTAssertEqual(error as? CloudProtocolError, .authenticationFailed)
        }

        var tampered = frame
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(
            try CloudObjectChunkV1.open(
                tampered,
                cloudVaultKey: cloudVaultKey,
                header: header
            )
        ) { error in
            XCTAssertEqual(error as? CloudProtocolError, .authenticationFailed)
        }
    }

    func testRecoveryEnvelopeHeaderVectorIsCanonical() throws {
        let header = CloudRecoveryEnvelopeHeaderV1(
            accountKeyID: fixtureAccountID,
            envelopeGeneration: 7,
            kdfSalt: Data(0x00...0x0f)
        )

        XCTAssertEqual(
            try header.encoded(),
            try Data(cloudHex: """
            4b4843524543310001000000010000000100000000112233445566778899aabb
            ccddeeff0700000000000000000102030405060708090a0b0c0d0e0f
            """)
        )
        XCTAssertEqual(
            try header.authenticationData(),
            try Data(cloudHex: """
            6b6579686f6c6c6f772e636c6f75642e7265636f766572792d656e76656c6f
            70652e7631004b48435245433100010000000100000001000000001122334455
            66778899aabbccddeeff0700000000000000000102030405060708090a0b0c0d
            0e0f
            """)
        )
        XCTAssertEqual(
            try CloudRecoveryEnvelopeHeaderV1(decoding: header.encoded()),
            header
        )
    }

    func testVaultKeyEnvelopeHeaderVectorIsCanonical() throws {
        let header = CloudVaultKeyEnvelopeHeaderV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            vaultKeyID: fixtureObjectID,
            accountKeyGeneration: 3
        )

        XCTAssertEqual(
            try header.encoded(),
            try Data(cloudHex: """
            4b4843564b455900010000000100000000112233445566778899aabbccddeeff
            ffeeddccbbaa99887766554433221100aaaaaaaabbbbccccddddeeeeeeeeeeee03
            00000000000000
            """)
        )
        XCTAssertEqual(
            try CloudVaultKeyEnvelopeHeaderV1(decoding: header.encoded()),
            header
        )
    }

    func testObjectHeaderAndChunkAADVectorsAreCanonical() throws {
        let header = CloudObjectHeaderV1(
            purpose: .content,
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            objectID: fixtureObjectID,
            objectVersion: 4,
            plaintextByteCount: 1_048_600,
            chunkCount: 2
        )

        XCTAssertEqual(
            try header.encoded(),
            try Data(cloudHex: """
            4b48434f424a310001000000010000000200112233445566778899aabbccddeeff
            ffeeddccbbaa99887766554433221100aaaaaaaabbbbccccddddeeeeeeeeeeee04
            0000000000000018001000000000000000100002000000
            """)
        )
        XCTAssertEqual(
            try header.chunkKeyInfo(sequence: 1),
            try Data(cloudHex: """
            02aaaaaaaabbbbccccddddeeeeeeeeeeee040000000000000001000000
            """)
        )
        XCTAssertEqual(
            try header.authenticationData(
                sequence: 1,
                isFinal: true,
                declaredPlaintextByteCount: 24
            ),
            try Data(cloudHex: """
            6b6579686f6c6c6f772e636c6f75642e6f626a6563742d6368756e6b2e7631
            004b48434f424a310001000000010000000200112233445566778899aabbccdd
            eeffffeeddccbbaa99887766554433221100aaaaaaaabbbbccccddddeeeeeeeeee
            ee040000000000000018001000000000000000100002000000010000000118
            000000
            """)
        )
        XCTAssertEqual(try CloudObjectHeaderV1(decoding: header.encoded()), header)
    }

    func testManifestVectorRoundTripsExactly() throws {
        let manifest = try fixtureManifest()
        let encoded = try manifest.encoded()
        let expected = try Data(cloudHex: """
        4b48434d414e31000100000000112233445566778899aabbccddeeffffeeddcc
        bbaa99887766554433221100102030405060708090a0b0c0d0e0f000010000
        0000000000007b30fd7790010000010000000100000011111111222233334444
        555555555555010c0000006d616e69666573742e6b686daaaaaaaabbbbccccdd
        ddeeeeeeeeeeee01000000000000001c00000000000000000102030405060708
        090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f9e00000000000000
        202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
        01000000
        """)

        XCTAssertEqual(encoded, expected)
        XCTAssertEqual(
            Data(SHA256.hash(data: encoded)),
            try Data(cloudHex: "1f8b86ba403f7856f62360660f50ca4c6e7d64758954e63eae26cf6437a4b089")
        )
        XCTAssertEqual(try CloudManifestV1(decoding: encoded), manifest)
    }

    func testManifestRejectsTrailingDataAndUnsupportedVersion() throws {
        var trailing = try fixtureManifest().encoded()
        trailing.append(0xff)
        XCTAssertThrowsError(try CloudManifestV1(decoding: trailing)) { error in
            XCTAssertEqual(error as? CloudProtocolError, .trailingData)
        }

        var future = try fixtureManifest().encoded()
        future[8] = 2
        XCTAssertThrowsError(try CloudManifestV1(decoding: future)) { error in
            XCTAssertEqual(error as? CloudProtocolError, .unsupportedVersion)
        }
    }

    func testManifestRejectsImpossibleEntryCountBeforeAllocation() throws {
        var encoded = try fixtureManifest().encoded()
        encoded.replaceSubrange(81..<85, with: Data([0x41, 0x0d, 0x03, 0x00]))

        XCTAssertThrowsError(try CloudManifestV1(decoding: encoded)) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidLength("manifest entry count")
            )
        }
    }

    func testManifestRejectsDuplicateObjectIdentifiers() throws {
        let first = try fixtureManifestEntry()
        let second = CloudManifestEntryV1(
            entryID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            role: .encryptedOriginal,
            localStorageName: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.khp",
            cloudObjectID: first.cloudObjectID,
            cloudObjectVersion: 1,
            innerCiphertextByteCount: 28,
            innerCiphertextSHA256: Data(repeating: 0x44, count: 32),
            storedCloudObjectByteCount: 158,
            storedCloudObjectSHA256: Data(repeating: 0x55, count: 32),
            chunkCount: 1
        )
        let manifest = CloudManifestV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            snapshotID: fixtureSnapshotID,
            generation: 1,
            parent: nil,
            createdAtMilliseconds: 1_720_000_000_123,
            entries: [first, second]
        )

        XCTAssertThrowsError(try manifest.encoded()) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .duplicateIdentifier("cloud object ID")
            )
        }
    }

    func testLaterGenerationRequiresExactParent() throws {
        let missingParent = CloudManifestV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            snapshotID: fixtureSnapshotID,
            generation: 2,
            parent: nil,
            createdAtMilliseconds: 1_720_000_000_123,
            entries: [try fixtureManifestEntry()]
        )
        XCTAssertThrowsError(try missingParent.encoded()) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidValue("manifest parent generation")
            )
        }

        let wrongParent = CloudManifestV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            snapshotID: fixtureSnapshotID,
            generation: 3,
            parent: CloudManifestParentV1(
                generation: 1,
                manifestObjectID: fixtureObjectID,
                storedObjectSHA256: Data(repeating: 0x66, count: 32)
            ),
            createdAtMilliseconds: 1_720_000_000_123,
            entries: [try fixtureManifestEntry()]
        )
        XCTAssertThrowsError(try wrongParent.encoded()) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidValue("manifest parent generation")
            )
        }
    }

    func testManifestRejectsUnsafeLocalStorageName() throws {
        let entry = CloudManifestEntryV1(
            entryID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            role: .encryptedOriginal,
            localStorageName: "../escape.khp",
            cloudObjectID: fixtureObjectID,
            cloudObjectVersion: 1,
            innerCiphertextByteCount: 28,
            innerCiphertextSHA256: Data(repeating: 0x44, count: 32),
            storedCloudObjectByteCount: 158,
            storedCloudObjectSHA256: Data(repeating: 0x55, count: 32),
            chunkCount: 1
        )

        XCTAssertThrowsError(try entry.validate()) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidValue("local storage name")
            )
        }
    }

    func testObjectAADRejectsRelabeledFinalChunkAndWrongLength() throws {
        let header = CloudObjectHeaderV1(
            purpose: .content,
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            objectID: fixtureObjectID,
            objectVersion: 1,
            plaintextByteCount: 1_048_600,
            chunkCount: 2
        )

        XCTAssertThrowsError(
            try header.authenticationData(
                sequence: 0,
                isFinal: true,
                declaredPlaintextByteCount: 1_048_576
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidValue("cloud-object final flag")
            )
        }
        XCTAssertThrowsError(
            try header.authenticationData(
                sequence: 1,
                isFinal: true,
                declaredPlaintextByteCount: 23
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProtocolError,
                .invalidLength("cloud-object chunk")
            )
        }
    }

    private var fixtureAccountID: UUID {
        UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
    }

    private var fixtureVaultID: UUID {
        UUID(uuidString: "ffeeddcc-bbaa-9988-7766-554433221100")!
    }

    private var fixtureSnapshotID: UUID {
        UUID(uuidString: "10203040-5060-7080-90a0-b0c0d0e0f000")!
    }

    private var fixtureObjectID: UUID {
        UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    }

    private func fixtureManifestEntry() throws -> CloudManifestEntryV1 {
        CloudManifestEntryV1(
            entryID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            role: .localManifest,
            localStorageName: "manifest.khm",
            cloudObjectID: fixtureObjectID,
            cloudObjectVersion: 1,
            innerCiphertextByteCount: 28,
            innerCiphertextSHA256: Data(0x00...0x1f),
            storedCloudObjectByteCount: try CloudObjectHeaderV1.storedByteCount(
                plaintextByteCount: 28,
                chunkCount: 1
            ),
            storedCloudObjectSHA256: Data(0x20...0x3f),
            chunkCount: 1
        )
    }

    private func fixtureManifest() throws -> CloudManifestV1 {
        CloudManifestV1(
            accountID: fixtureAccountID,
            vaultID: fixtureVaultID,
            snapshotID: fixtureSnapshotID,
            generation: 1,
            parent: nil,
            createdAtMilliseconds: 1_720_000_000_123,
            entries: [try fixtureManifestEntry()]
        )
    }
}

private extension Data {
    init(cloudHex: String) throws {
        let compact = cloudHex.filter { !$0.isWhitespace }
        guard compact.count.isMultiple(of: 2) else {
            throw CloudProtocolError.invalidLength("hex fixture")
        }

        var result = Data()
        result.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw CloudProtocolError.invalidValue("hex fixture")
            }
            result.append(byte)
            index = next
        }
        self = result
    }
}

private extension SymmetricKey {
    var cloudData: Data {
        withUnsafeBytes { Data($0) }
    }
}

private struct FixtureCloudRecoveryKeyDeriver: CloudRecoveryKeyDeriving {
    let key: Data

    func derive(
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1
    ) throws -> SymmetricKey {
        SymmetricKey(data: key)
    }
}
