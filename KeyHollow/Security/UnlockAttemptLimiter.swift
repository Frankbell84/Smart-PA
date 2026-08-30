import Foundation

actor UnlockAttemptLimiter {
    enum LimitError: Error {
        case temporarilyLocked(until: Date)
    }

    private let defaults: UserDefaults
    private let countKey = "keyhollow.unlock.failure-count.v2"
    private let blockedUntilKey = "keyhollow.unlock.blocked-until.v2"
    private let lastFailureKey = "keyhollow.unlock.last-failure.v2"

    /// Old failures eventually stop penalizing a legitimate user, but a valid
    /// passcode for one vault cannot immediately erase the guessing history for
    /// every other vault on the device.
    private let decayWindow: TimeInterval = 12 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func checkAllowed(now: Date = Date()) throws {
        decayIfNeeded(now: now)

        let blockedUntil = defaults.object(forKey: blockedUntilKey) as? Date
        if let blockedUntil, blockedUntil > now {
            throw LimitError.temporarilyLocked(until: blockedUntil)
        }
    }

    func recordFailure(now: Date = Date()) {
        decayIfNeeded(now: now)

        let failures = defaults.integer(forKey: countKey) + 1
        defaults.set(failures, forKey: countKey)
        defaults.set(now, forKey: lastFailureKey)

        let delay: TimeInterval
        switch failures {
        case 0...4: delay = 0
        case 5...7: delay = 5
        case 8...10: delay = 30
        case 11...13: delay = 5 * 60
        default: delay = 15 * 60
        }

        if delay > 0 {
            defaults.set(now.addingTimeInterval(delay), forKey: blockedUntilKey)
        }
    }

    /// Intentionally does not reset failure history. In a multi-vault product,
    /// someone who legitimately knows Vault A's passcode must not be able to
    /// alternate Vault A successes with guesses against Vault B to defeat the
    /// global online-guessing throttle.
    func recordSuccess(now: Date = Date()) {
        decayIfNeeded(now: now)
        defaults.removeObject(forKey: blockedUntilKey)
    }

    private func decayIfNeeded(now: Date) {
        guard let lastFailure = defaults.object(forKey: lastFailureKey) as? Date else { return }
        guard now.timeIntervalSince(lastFailure) >= decayWindow else { return }

        defaults.removeObject(forKey: countKey)
        defaults.removeObject(forKey: blockedUntilKey)
        defaults.removeObject(forKey: lastFailureKey)
    }
}
