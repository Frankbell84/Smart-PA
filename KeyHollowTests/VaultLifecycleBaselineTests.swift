import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class VaultLifecycleBaselineTests: XCTestCase {
    @MainActor
    func testCompleteVaultLifecyclePersistsAndRemovesAccess() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }

        var service = try fixture.makeService()
        XCTAssertFalse(try await service.hasAnyVaults())

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        XCTAssertTrue(try await service.hasAnyVaults())

        let vaultPhotoRoot = fixture.photoRoot.appendingPathComponent(
            created.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        let photoStore = try VaultPhotoStore(
            vaultID: created.vaultID,
            vaultKey: created.vaultKey,
            storageRoot: vaultPhotoRoot
        )
        let photo = try await photoStore.importPhoto(
            originalData: Data("lifecycle original".utf8),
            thumbnailData: Data("lifecycle thumbnail".utf8)
        )
        XCTAssertEqual(try await photoStore.loadPhoto(photo), Data("lifecycle original".utf8))

        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        XCTAssertTrue(session.isUnlocked)
        session.lock()
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertNil(session.withActiveKey { $0 })

        // A new service instance models terminating and relaunching the app.
        service = try fixture.makeService()
        XCTAssertTrue(try await service.hasAnyVaults())
        XCTAssertTrue(fixture.credentialFiles().contains { $0.pathExtension == "khv" })
        XCTAssertFalse(fixture.credentialFiles().contains { $0.pathExtension == "khvtmp" })

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
        XCTAssertEqual(reopened.vaultKey.bytes, created.vaultKey.bytes)

        let changed = try await service.changePasscode(
            currentPasscode: fixture.originalPasscode,
            newPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )
        XCTAssertEqual(changed.vaultID, created.vaultID)
        XCTAssertEqual(changed.vaultKey.bytes, created.vaultKey.bytes)
        await assertInvalidCredentials {
            try await service.unlock(passcode: fixture.originalPasscode)
        }

        let reopenedWithNewPasscode = try await service.unlock(
            passcode: fixture.replacementPasscode
        )
        XCTAssertEqual(reopenedWithNewPasscode.vaultID, created.vaultID)
        XCTAssertEqual(reopenedWithNewPasscode.vaultKey.bytes, created.vaultKey.bytes)

        try await service.deleteVault(
            currentPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )
        XCTAssertFalse(try await service.hasAnyVaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultPhotoRoot.path))
        await assertInvalidCredentials {
            try await service.unlock(passcode: fixture.replacementPasscode)
        }
    }

    func testRejectedCreationAndDuplicatePasscodeDoNotChangePersistedVaults() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()

        do {
            _ = try await service.createVault(passcode: "12345678")
            XCTFail("A predictable LowKey created a vault")
        } catch KeyDerivationError.invalidPasscode {}
        XCTAssertFalse(try await service.hasAnyVaults())

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        do {
            _ = try await service.createVault(passcode: fixture.originalPasscode)
            XCTFail("A duplicate LowKey created another vault")
        } catch VaultUnlockError.passcodeAlreadyUsed {}

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 1)
    }

    func testFailedPasscodeChangeAndDeleteLeaveIndependentVaultsAccessible() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()

        let first = try await service.createVault(passcode: fixture.originalPasscode)
        let second = try await service.createVault(passcode: fixture.secondVaultPasscode)

        do {
            _ = try await service.changePasscode(
                currentPasscode: fixture.originalPasscode,
                newPasscode: fixture.secondVaultPasscode,
                expectedVaultID: first.vaultID
            )
            XCTFail("A passcode change replaced another vault credential")
        } catch VaultUnlockError.passcodeAlreadyUsed {}

        await assertInvalidCredentials {
            try await service.deleteVault(
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: second.vaultID
            )
        }

        XCTAssertEqual(
            try await service.unlock(passcode: fixture.originalPasscode).vaultID,
            first.vaultID
        )
        XCTAssertEqual(
            try await service.unlock(passcode: fixture.secondVaultPasscode).vaultID,
            second.vaultID
        )
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 2)
    }

    private func assertInvalidCredentials(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Invalid credentials were accepted", file: file, line: line)
        } catch VaultUnlockError.invalidCredentials {
            return
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class LifecycleFixture: @unchecked Sendable {
    let root: URL
    let credentialRoot: URL
    let photoRoot: URL
    let defaults: UserDefaults
    let defaultsSuite: String

    let originalPasscode = "83057291"
    let replacementPasscode = "60483927"
    let secondVaultPasscode = "27594086"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowLifecycleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        credentialRoot = root.appendingPathComponent("credentials", isDirectory: true)
        photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)

        defaultsSuite = "KeyHollowLifecycleTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: defaultsSuite) else {
            throw CocoaError(.featureUnsupported)
        }
        defaults = isolatedDefaults
    }

    func makeService() throws -> VaultUnlockService {
        try VaultUnlockService(
            kdf: FastLifecycleKDF(),
            limiter: UnlockAttemptLimiter(defaults: defaults),
            secrets: FixedDeviceSecrets(),
            vaultStorageRootOverride: credentialRoot,
            photoStorageRootOverride: photoRoot
        )
    }

    func credentialFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: credentialRoot,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FixedDeviceSecrets: DeviceSecretProviding {
    func loadOrCreate() throws -> Data {
        Data(repeating: 0x51, count: 32)
    }

    func loadOrCreateInstallationSalt() throws -> Data {
        Data(repeating: 0xA7, count: 16)
    }
}

private struct FastLifecycleKDF: PasswordKeyDeriving {
    func deriveKey(passcode: String, installationSalt: Data, pepper: Data) throws -> SymmetricKey {
        var input = Data(passcode.utf8)
        input.append(installationSalt)
        input.append(pepper)
        return SymmetricKey(data: Data(SHA256.hash(data: input)))
    }
}

private extension SymmetricKey {
    var bytes: Data {
        withUnsafeBytes { Data($0) }
    }
}
