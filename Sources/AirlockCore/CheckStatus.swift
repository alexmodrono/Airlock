// CheckStatus.swift
// Airlock

import Foundation

/// The status of a flight check during the onboarding process.
public enum CheckStatus: Equatable {
    /// Check has not yet been evaluated
    case pending
    /// Check is currently being validated
    case checking
    /// Check requires user action (button is enabled)
    case active
    /// Check passed successfully
    case success
    /// Check failed with an error
    case failed(CheckError)

    public static func == (lhs: CheckStatus, rhs: CheckStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.checking, .checking),
             (.active, .active),
             (.success, .success):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// A check-specific error with user-facing description.
public struct CheckError: Error, LocalizedError {
    public let message: String
    public let recoveryAction: String?

    public init(message: String, recoveryAction: String? = nil) {
        self.message = message
        self.recoveryAction = recoveryAction
    }

    public var errorDescription: String? { message }
}
