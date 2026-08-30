import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class SecurityCryptoTests: XCTestCase {
    func testPasscodesRequireAtLeastEightDigitsEverywhere() {
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("000000"))
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("1234567"))
        XCTAssertTrue(PasscodePolicy.isValidForUnlock("83057291"))
        XCTAssertFalse(PasscodePolicy.isValidForUnlock("83057291x"))
    }

    func testNewPasscodeGuardrailsRejectPredictableChoices() {
        let rejected = [
            "000000",
            "00000000",
            "111111111",
            "12345678",
            "123456789",
            "987654321",
            "78901234",
            "12121212",
            "12341234",
            "11111234"
        ]

        for passcode in rejected {
            XCTAssertFalse(
                PasscodePolicy.isAcceptableNewPasscode(passcode),
                "Predictable passcode should be rejected: \(passcode)"
            )
        }

        XCTAssertTrue(PasscodePolicy.isAcceptableNewPasscode("83057291"))
        XCTAssertTrue(PasscodePolicy.isAcceptableNewPasscode("8305729146"))
    }

    func testSecurityTiersStartAtEightDigits() {
        XCTAssertEqual(PasscodeTier.standard.fixedLength, 8)
        XCTAssertEqual(PasscodeTier.enhanced.fixedLength, 10)
        XCTAssertEqual(PasscodeTier.high.fixedLength, 12)
        XCTAssertEqual(PasscodeTier.maximum.fixedLength, 16)

        XCTAssertTrue(
            PasscodePolicy.isAcceptableNewPasscode("83057291", tier: .standard)
        )
        XCTAssertFalse(
            PasscodePolicy.isAcceptableNewPasscode("83057291", tier: .enhanced)
        )
    }

    func testRFC9106Argon2idVector() throws {
        let tag = try Argon2id.deriveBytes(
            password: Data(repeating: 0x01, count: 32),
            salt: Data(repeating: 0x02, count: 16),
            memoryKiB: 32,
            iterations: 3,
            parallelism: 4,
            outputByteCount: 32,
            secret: Data(repeating: 0x03, count: 8),
            associatedData: Data(repeating: 0x04, count: 12)
        )

        XCTAssertEqual(
            tag,
            try Data(hex: "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
        )
    }

    func testAESGCMRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("KeyHollow authenticated encryption test".utf8)
        let ciphertext = try CryptoBox.seal(plaintext, using: key)

        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(try CryptoBox.open(ciphertext, using: key), plaintext)
    }

    func testAESGCMTamperFailsClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("private photo bytes".utf8)
        var ciphertext = try CryptoBox.seal(plaintext, using: key)
        XCTAssertFalse(ciphertext.isEmpty)

        ciphertext[ciphertext.index(before: ciphertext.endIndex)] ^= 0x01
        XCTAssertThrowsError(try CryptoBox.open(ciphertext, using: key))
    }

    func testVaultSubkeysAreDomainSeparated() {
        let vaultKey = SymmetricKey(size: .bits256)
        let id = UUID()

        let manifest = VaultPhotoKeySchedule.manifestKey(from: vaultKey).bytes
        let photo = VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id).bytes
        let thumbnail = VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id).bytes

        XCTAssertNotEqual(manifest, photo)
        XCTAssertNotEqual(manifest, thumbnail)
        XCTAssertNotEqual(photo, thumbnail)
    }

    func testVaultEnvelopeCanBeRewrappedWithoutChangingVaultKey() throws {
        let oldUnlockKey = SymmetricKey(size: .bits256)
        let newUnlockKey = SymmetricKey(size: .bits256)
        let created = try VaultEnvelope.create(using: oldUnlockKey)

        let replacement = try VaultEnvelope.seal(payload: created.payload, using: newUnlockKey)
        let reopened = try replacement.open(using: newUnlockKey)

        XCTAssertEqual(reopened.vaultID, created.payload.vaultID)
        XCTAssertEqual(reopened.vaultKey, created.payload.vaultKey)
        XCTAssertEqual(reopened.createdAt, created.payload.createdAt)
        XCTAssertThrowsError(try replacement.open(using: oldUnlockKey))
    }

    func testSuccessfulUnlockDoesNotEraseGlobalFailureBudget() async throws {
        let suite = "KeyHollowTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let limiter = UnlockAttemptLimiter(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)

        for _ in 0..<5 {
            await limiter.recordFailure(now: start)
        }

        // A legitimate unlock may clear the completed active cooldown so the
        // user can enter a known vault, but it must preserve the accumulated
        // failure count. The next bad guess must therefore resume throttling.
        let afterInitialCooldown = start.addingTimeInterval(6)
        await limiter.recordSuccess(now: afterInitialCooldown)
        await limiter.recordFailure(now: afterInitialCooldown)

        do {
            try await limiter.checkAllowed(now: afterInitialCooldown.addingTimeInterval(1))
            XCTFail("A valid vault unlock erased the multi-vault guessing history")
        } catch UnlockAttemptLimiter.LimitError.temporarilyLocked(let until) {
            XCTAssertGreaterThan(until, afterInitialCooldown.addingTimeInterval(1))
        } catch {
            XCTFail("Unexpected limiter error: \(error)")
        }
    }
}

private extension SymmetricKey {
    var bytes: Data {
        withUnsafeBytes { Data($0) }
    }
}

private extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else { throw HexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw HexError.invalid }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    enum HexError: Error { case invalid }
}
