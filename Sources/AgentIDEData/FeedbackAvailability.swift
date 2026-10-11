import AgentIDEDomain

/// Counts use the same eligible items as the clipboard prompt, never event claims.
public struct FeedbackAvailability: Sendable {
    public let counts: [AutofixAttempt.Kind: Int]
    public let localReview: LocalReview?
    public let summary: PullRequestSummary?
    public let hasMatchingHead: Bool

    public var itemCount: Int {
        counts.values.reduce(0, +)
    }

    public var canCopy: Bool {
        counts.isEmpty == false
    }
}
