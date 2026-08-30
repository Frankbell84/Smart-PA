import Foundation

actor UnlockAttemptLimiter {
    enum LimitError: Error {
        case temporarilyLocked(until: Date)
    }

    private let defaults: UserDefaults
    private let countKey = "keyhollow.unlock.failure-count.v1"
    private let blockedUntilKey = "keyhollow.unlock.blocked-until.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func checkAllowed(now: Date = Date()) throws {
        let blockedUntil = defaults.object(forKey: blockedUntilKey) as? Date
        if let blockedUntil, blockedUntil > now {
            throw LimitError.temporarilyLocked(until: blockedUntil)
        }
    }

    func recordFailure(now: Date = Date()) {
        let failures = defaults.integer(forKey: countKey) + 1
        defaults.set(failures, forKey: countKey)

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

    func recordSuccess() {
        defaults.removeObject(forKey: countKey)
        defaults.removeObject(forKey: blockedUntilKey)
    }
}
