import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowVaultCore

final class PortableArchiveSecurityTests: XCTestCase {
    func testGeneratedRecoveryCodeCreatesPortableAuthenticatedEnvelope() throws {
        let recoveryCode = try PortableArchiveRecoveryCode.generate()
        let credential = PortableArchiveCredential.recoveryCode(recoveryCode)
        let payload = testVaultPayload()

        let header = try EncryptedVaultArchiveHeader.create(
            vaultPayload: payload,
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )
        let opened = try header.open(
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )

        XCTAssertEqual(try PortableArchiveRecoveryCode.canonicalize(recoveryCode).count, 32)
        XCTAssertEqual(opened.sourceVaultID, payload.vaultID)
        XCTAssertEqual(opened.sourceVaultCreatedAt, payload.createdAt)
        XCTAssertEqual(opened.vaultKey, payload.vaultKey)
        XCTAssertEqual(opened.contentKey.count, 32)
        XCTAssertNotEqual(opened.vaultKey, opened.contentKey)
    }

    func testRecoveryCodeAllowsUnambiguousFormatting() throws {
        let canonical = "01ABCDEFGHJKMNPQRSTVWXYZ23456789"
        let formatted = "O1AB-CDEF-GHJK-MNPQ-RSTV-WXYZ-2345-6789"

        XCTAssertEqual(
            try PortableArchiveRecoveryCode.canonicalize(formatted),
            canonical
        )
    }

    func testWrongRecoveryCodeFailsClosed() throws {
        let payload = testVaultPayload()
        let header = try EncryptedVaultArchiveHeader.create(
            vaultPayload: payload,
            credential: .recoveryCode("0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
            keyDeriver: TestArchiveKeyDeriver()
        )

        XCTAssertThrowsError(
            try header.open(
                credential: .recoveryCode("1123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .authenticationFailed)
        }
    }

    func testTamperedSealedSecretsFailClosed() throws {
        let credential = PortableArchiveCredential.passphrase("correct horse battery staple")
        let original = try EncryptedVaultArchiveHeader.create(
            vaultPayload: testVaultPayload(),
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )
        var tamperedSecrets = original.sealedSecrets
        tamperedSecrets[tamperedSecrets.index(before: tamperedSecrets.endIndex)] ^= 0x01
        let tampered = EncryptedVaultArchiveHeader(
            format: original.format,
            version: original.version,
            kdf: original.kdf,
            sealedSecrets: tamperedSecrets
        )

        XCTAssertThrowsError(
            try tampered.open(
                credential: credential,
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .authenticationFailed)
        }
    }

    func testUnsupportedHeaderIdentityFailsClosed() throws {
        let credential = PortableArchiveCredential.passphrase("correct horse battery staple")
        let original = try EncryptedVaultArchiveHeader.create(
            vaultPayload: testVaultPayload(),
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )
        let wrongFormat = EncryptedVaultArchiveHeader(
            format: "com.example.not-keyhollow",
            version: original.version,
            kdf: original.kdf,
            sealedSecrets: original.sealedSecrets
        )
        let futureVersion = EncryptedVaultArchiveHeader(
            format: original.format,
            version: original.version + 1,
            kdf: original.kdf,
            sealedSecrets: original.sealedSecrets
        )

        XCTAssertThrowsError(
            try wrongFormat.open(
                credential: credential,
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .invalidHeader)
        }
        XCTAssertThrowsError(
            try futureVersion.open(
                credential: credential,
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .unsupportedVersion)
        }
    }

    func testAlteredKDFParametersAreRejectedBeforeDerivation() throws {
        let original = try EncryptedVaultArchiveHeader.create(
            vaultPayload: testVaultPayload(),
            credential: .passphrase("correct horse battery staple"),
            keyDeriver: TestArchiveKeyDeriver()
        )
        let hostileKDF = PortableArchiveKDFParameters(
            algorithm: original.kdf.algorithm,
            salt: original.kdf.salt,
            memoryKiB: UInt32.max,
            iterations: original.kdf.iterations,
            parallelism: original.kdf.parallelism,
            outputByteCount: original.kdf.outputByteCount
        )
        let hostileHeader = EncryptedVaultArchiveHeader(
            format: original.format,
            version: original.version,
            kdf: hostileKDF,
            sealedSecrets: original.sealedSecrets
        )

        XCTAssertThrowsError(
            try hostileHeader.open(
                credential: .passphrase("correct horse battery staple"),
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .invalidKDFParameters)
        }
    }

    func testAlteredSaltFailsHeaderAuthentication() throws {
        let credential = PortableArchiveCredential.passphrase("correct horse battery staple")
        let original = try EncryptedVaultArchiveHeader.create(
            vaultPayload: testVaultPayload(),
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )
        var alteredSalt = original.kdf.salt
        alteredSalt[alteredSalt.startIndex] ^= 0x01
        let alteredKDF = PortableArchiveKDFParameters(
            algorithm: original.kdf.algorithm,
            salt: alteredSalt,
            memoryKiB: original.kdf.memoryKiB,
            iterations: original.kdf.iterations,
            parallelism: original.kdf.parallelism,
            outputByteCount: original.kdf.outputByteCount
        )
        let tampered = EncryptedVaultArchiveHeader(
            format: original.format,
            version: original.version,
            kdf: alteredKDF,
            sealedSecrets: original.sealedSecrets
        )

        XCTAssertThrowsError(
            try tampered.open(
                credential: credential,
                keyDeriver: TestArchiveKeyDeriver()
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveError, .authenticationFailed)
        }
    }

    func testGeneratedHeadersUseUniqueAESGCMNonces() throws {
        let credential = PortableArchiveCredential.passphrase("correct horse battery staple")
        var observedNonces = Set<Data>()

        for _ in 0..<1_000 {
            let header = try EncryptedVaultArchiveHeader.create(
                vaultPayload: testVaultPayload(),
                credential: credential,
                keyDeriver: TestArchiveKeyDeriver()
            )
            let sealedBox = try AES.GCM.SealedBox(combined: header.sealedSecrets)
            let nonce = Data(sealedBox.nonce)

            XCTAssertTrue(observedNonces.insert(nonce).inserted, "AES-GCM nonce repeated")
        }
    }

    func testDeterministicHeaderVectorRemainsCompatible() throws {
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let kdf = PortableArchiveKDFParameters(
            algorithm: PortableArchiveKDFParameters.algorithmIdentifier,
            salt: Data(0x00...0x0f),
            memoryKiB: PortableArchiveKDFParameters.memoryKiB,
            iterations: PortableArchiveKDFParameters.iterations,
            parallelism: PortableArchiveKDFParameters.parallelism,
            outputByteCount: PortableArchiveKDFParameters.outputByteCount
        )
        let expectedAAD = try Data(hex: """
        6b6579686f6c6c6f772e656e637279707465642d7661756c742e68656164657200
        6172676f6e3269642d76312e33000100000000000100030000000200000020000000
        000102030405060708090a0b0c0d0e0f
        """)
        XCTAssertEqual(kdf.authenticationData(archiveVersion: 1), expectedAAD)

        let plaintext = Data("""
        {"archiveID":"00112233-4455-6677-8899-aabbccddeeff","sourceVaultID":"ffeeddcc-bbaa-9988-7766-554433221100","sourceVaultCreatedAt":0,"exportedAt":3600,"vaultKey":"ERERERERERERERERERERERERERERERERERERERERERE=","contentKey":"IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI="}
        """.utf8)
        let wrappingKey = try TestArchiveKeyDeriver().deriveWrappingKey(
            credential: credential,
            parameters: kdf
        )
        let nonce = try AES.GCM.Nonce(data: Data(0x00...0x0b))
        let sealed = try AES.GCM.seal(
            plaintext,
            using: wrappingKey,
            nonce: nonce,
            authenticating: expectedAAD
        )
        let expectedCombined = try Data(hex: """
        000102030405060708090a0b9df97ec5522e85a15d3a5213bdec2ea97ef96ca3
        9ea1d21fefe583323cd169598daf68c1db3a3d572d41a4d387e2bd59f7b17cb3
        4d1786fc926e1fc44b778c590dde22b86e69918fbc9d395dd7482b846ed8f885
        9090ff1b3113ef64738434b03770db40b2a027b6dc16707f3613d849f9ce8305
        ebb8b91168d0ff6e146b9acca68e251ec0ad3ae8f4daf8ea9f91b1934cd746c7
        32879d4d4070280589a6353a0203a8d0413e3c7b860d1a58c048f55a814ccdc
        aa13aa04f3b2ef9a8412c4c33cdf6f8457d02ca87ab3851cbe92fed68649a953
        55d4d6cad5bfc1e4b44a9500e2d13b13f1d67e192ea8495c8e398b8086225ba
        4127297c0030ff4c24180faebf26b8e04534d4205dcfed5eaa0424c7e6eba377
        bf01fea325f3b2150b
        """)
        XCTAssertEqual(sealed.combined, expectedCombined)

        let header = EncryptedVaultArchiveHeader(
            format: EncryptedVaultArchiveHeader.formatIdentifier,
            version: EncryptedVaultArchiveHeader.currentVersion,
            kdf: kdf,
            sealedSecrets: expectedCombined
        )
        let opened = try header.open(
            credential: credential,
            keyDeriver: TestArchiveKeyDeriver()
        )

        XCTAssertEqual(opened.archiveID.uuidString.lowercased(), "00112233-4455-6677-8899-aabbccddeeff")
        XCTAssertEqual(opened.sourceVaultID.uuidString.lowercased(), "ffeeddcc-bbaa-9988-7766-554433221100")
        XCTAssertEqual(opened.sourceVaultCreatedAt, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(opened.exportedAt, Date(timeIntervalSinceReferenceDate: 3_600))
        XCTAssertEqual(opened.vaultKey, Data(repeating: 0x11, count: 32))
        XCTAssertEqual(opened.contentKey, Data(repeating: 0x22, count: 32))
    }

    func testWeakOrAmbiguousPassphrasesAreRejected() {
        let rejected = [
            "too short",
            "aaaaaaaaaaaaaaaa",
            " leading spaces are unsafe",
            "trailing spaces are unsafe "
        ]

        for passphrase in rejected {
            XCTAssertThrowsError(
                try TestArchiveKeyDeriver().deriveWrappingKey(
                    credential: .passphrase(passphrase),
                    parameters: .testFixture
                ),
                "Passphrase should be rejected: \(passphrase)"
            )
        }
    }

    private func testVaultPayload() -> VaultPayload {
        VaultPayload(
            vaultID: UUID(),
            vaultKey: Data(repeating: 0x3a, count: 32),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct TestArchiveKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        var input = try credential.keyMaterial()
        input.append(parameters.salt)
        return SymmetricKey(data: SHA256.hash(data: input))
    }
}

private extension PortableArchiveKDFParameters {
    static var testFixture: PortableArchiveKDFParameters {
        PortableArchiveKDFParameters(
            algorithm: algorithmIdentifier,
            salt: Data(repeating: 0x2b, count: saltByteCount),
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism,
            outputByteCount: outputByteCount
        )
    }
}

private extension Data {
    init(hex: String) throws {
        let compact = hex.filter { !$0.isWhitespace }
        guard compact.count.isMultiple(of: 2) else { throw HexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw HexError.invalid
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    enum HexError: Error { case invalid }
}

