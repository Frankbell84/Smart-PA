import Foundation

enum PasscodeTier: String, CaseIterable, Codable, Identifiable {
    case standard
    case enhanced
    case high
    case maximum
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .enhanced: return "Enhanced"
        case .high: return "High"
        case .maximum: return "Maximum"
        case .custom: return "Custom"
        }
    }

    var fixedLength: Int? {
        switch self {
        case .standard: return 8
        case .enhanced: return 10
        case .high: return 12
        case .maximum: return 16
        case .custom: return nil
        }
    }
}

enum NewPasscodeRejection: Equatable {
    case tooShort
    case tooLong
    case digitsOnly
    case tooRepetitive
    case sequential
    case repeatedPattern

    var message: String {
        switch self {
        case .tooShort:
            return "Use at least 8 digits."
        case .tooLong:
            return "Use no more than 20 digits."
        case .digitsOnly:
            return "Use digits from 0 through 9 only."
        case .tooRepetitive:
            return "Use a less repetitive passcode with at least three different digits."
        case .sequential:
            return "Counting sequences such as 12345678 or 87654321 are not allowed."
        case .repeatedPattern:
            return "Repeated patterns such as 12121212 or 12341234 are not allowed."
        }
    }
}

enum PasscodePolicy {
    /// New and changed passcodes must meet the stronger current policy.
    static let minimumLength = 8
    static let maximumLength = 20

    static func isValidForUnlock(_ passcode: String) -> Bool {
        (minimumLength...maximumLength).contains(passcode.count) &&
        isASCIIDigits(passcode)
    }

    static func rejectionReason(forNewPasscode passcode: String) -> NewPasscodeRejection? {
        guard passcode.count >= minimumLength else { return .tooShort }
        guard passcode.count <= maximumLength else { return .tooLong }
        guard isASCIIDigits(passcode) else { return .digitsOnly }

        let digits = passcode.utf8.map { Int($0 - 48) }
        let frequencies = Dictionary(grouping: digits, by: { $0 }).mapValues(\.count)
        guard frequencies.count >= 3,
              (frequencies.values.max() ?? digits.count) * 2 <= digits.count else {
            return .tooRepetitive
        }

        let ascending = zip(digits, digits.dropFirst()).allSatisfy { pair in
            (pair.0 + 1) % 10 == pair.1
        }
        let descending = zip(digits, digits.dropFirst()).allSatisfy { pair in
            (pair.0 + 9) % 10 == pair.1
        }
        guard !ascending, !descending else { return .sequential }

        if digits.count >= 4 {
            for patternLength in 2...(digits.count / 2) where digits.count.isMultiple(of: patternLength) {
                let repeats = digits.indices.allSatisfy {
                    digits[$0] == digits[$0 % patternLength]
                }
                if repeats { return .repeatedPattern }
            }
        }

        return nil
    }

    static func isAcceptableNewPasscode(_ passcode: String) -> Bool {
        rejectionReason(forNewPasscode: passcode) == nil
    }

    static func isAcceptableNewPasscode(
        _ passcode: String,
        tier: PasscodeTier,
        customLength: Int? = nil
    ) -> Bool {
        guard isAcceptableNewPasscode(passcode) else { return false }
        if let fixedLength = tier.fixedLength {
            return passcode.count == fixedLength
        }
        guard let customLength,
              (minimumLength...maximumLength).contains(customLength) else { return false }
        return passcode.count == customLength
    }

    private static func isASCIIDigits(_ passcode: String) -> Bool {
        !passcode.isEmpty && passcode.utf8.allSatisfy { (48...57).contains($0) }
    }
}

