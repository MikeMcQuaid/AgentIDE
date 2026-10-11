import Foundation

// MARK: - FailedAutofixPush

public struct FailedAutofixPush: Codable, Equatable, Sendable {
    // MARK: Public

    public let id: UUID
    public let message: String
    public var retryRequested = false

    // MARK: Internal

    let attempt: AutofixAttempt
    let commit: String

    var attemptWithUnclaimedPush: AutofixAttempt {
        var result = attempt
        result.pushClaimed = false
        return result
    }
}

// MARK: - AutofixPushError

/// A failed transport must retain the tip produced by successful signing.
struct AutofixPushError: LocalizedError {
    let commit: String
    let errorDescription: String?
}

// MARK: - PullRequestAutomation

public extension PullRequestAutomation {
    /// The dashboard refresh retries only after this explicit user action.
    mutating func retryPush() {
        guard failedPush != nil, failedPush?.retryRequested == false else {
            return
        }

        failedPush?.retryRequested = true
        pending = "Preparing to retry the push through AgentIDE"
    }
}
