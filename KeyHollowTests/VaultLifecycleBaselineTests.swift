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
        var hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)

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
        let reopenedPhoto = try await photoStore.loadPhoto(photo)
        XCTAssertEqual(reopenedPhoto, Data("lifecycle original".utf8))

        let session = VaultSession()
        session.unlock(vaultID: created.vaultID, key: created.vaultKey)
        XCTAssertTrue(session.isUnlocked)
        session.lock()
        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertNil(session.withActiveKey { $0 })

        // A new service instance models terminating and relaunching the app.
        service = try fixture.makeService()
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)
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
        do {
            _ = try await service.unlock(passcode: fixture.originalPasscode)
            XCTFail("The previous LowKey remained valid after a successful change")
        } catch VaultUnlockError.invalidCredentials {}

        let reopenedWithNewPasscode = try await service.unlock(
            passcode: fixture.replacementPasscode
        )
        XCTAssertEqual(reopenedWithNewPasscode.vaultID, created.vaultID)
        XCTAssertEqual(reopenedWithNewPasscode.vaultKey.bytes, created.vaultKey.bytes)

        try await service.deleteVault(
            currentPasscode: fixture.replacementPasscode,
            expectedVaultID: created.vaultID
        )
        hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultPhotoRoot.path))
        do {
            _ = try await service.unlock(passcode: fixture.replacementPasscode)
            XCTFail("A deleted vault remained accessible")
        } catch VaultUnlockError.invalidCredentials {}
    }

    func testRejectedCreationAndDuplicatePasscodeDoNotChangePersistedVaults() async throws {
        let fixture = try LifecycleFixture()
        defer { fixture.cleanUp() }
        let service = try fixture.makeService()

        do {
            _ = try await service.createVault(passcode: "12345678")
            XCTFail("A predictable LowKey created a vault")
        } catch KeyDerivationError.invalidPasscode {}
        var hasVaults = try await service.hasAnyVaults()
        XCTAssertFalse(hasVaults)

        let created = try await service.createVault(passcode: fixture.originalPasscode)
        do {
            _ = try await service.createVault(passcode: fixture.originalPasscode)
            XCTFail("A duplicate LowKey created another vault")
        } catch VaultUnlockError.passcodeAlreadyUsed {}

        let reopened = try await service.unlock(passcode: fixture.originalPasscode)
        XCTAssertEqual(reopened.vaultID, created.vaultID)
        hasVaults = try await service.hasAnyVaults()
        XCTAssertTrue(hasVaults)
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

        do {
            try await service.deleteVault(
                currentPasscode: fixture.originalPasscode,
                expectedVaultID: second.vaultID
            )
            XCTFail("A mismatched vault identity was deleted")
        } catch VaultUnlockError.invalidCredentials {}

        let reopenedFirst = try await service.unlock(passcode: fixture.originalPasscode)
        let reopenedSecond = try await service.unlock(passcode: fixture.secondVaultPasscode)
        XCTAssertEqual(reopenedFirst.vaultID, first.vaultID)
        XCTAssertEqual(reopenedSecond.vaultID, second.vaultID)
        XCTAssertEqual(fixture.credentialFiles().filter { $0.pathExtension == "khv" }.count, 2)
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
