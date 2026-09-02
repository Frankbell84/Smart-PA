import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

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
