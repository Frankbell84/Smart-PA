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
        case .standard: return 6
        case .enhanced: return 8
        case .high: return 12
        case .maximum: return 16
        case .custom: return nil
        }
    }
}

enum PasscodePolicy {
    static let minimumLength = 6
    static let maximumLength = 20

    static func isValid(_ passcode: String) -> Bool {
        guard passcode.count >= minimumLength,
              passcode.count <= maximumLength else { return false }
        return passcode.allSatisfy(\.isNumber)
    }

    static func isValid(_ passcode: String, tier: PasscodeTier, customLength: Int? = nil) -> Bool {
        guard isValid(passcode) else { return false }
        if let fixedLength = tier.fixedLength {
            return passcode.count == fixedLength
        }
        guard let customLength,
              (minimumLength...maximumLength).contains(customLength) else { return false }
        return passcode.count == customLength
    }
}
