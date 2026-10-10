import AgentIDEDomain

// MARK: - AutofixDriver

/// One delivery and completion path, with I/O seams for race regression tests.
struct AutofixDriver {
    struct Target {
        let worktree: Worktree
        let session: AgentSession
        var allowsUncommitted = false
    }

    typealias Preparation = @Sendable (
        PullRequestAutomation, PullRequestSummary, AutofixCandidate,
    ) async throws -> String

    typealias Collection = @Sendable (PullRequestAutomation, Target, Bool) async throws -> LocalFeedbackCollection?

    let summary: @Sendable (PullRequestAutomation, Bool) async throws -> PullRequestSummary?
    let threads: @Sendable (PullRequestAutomation, Bool) async throws -> [ReviewThread]
    let writers: @Sendable (PullRequestAutomation, [ReviewThread], Bool) async -> Set<String>
    var localReview: @Sendable (PullRequestAutomation) async throws -> LocalReview? = { _ in nil }
    let target: @Sendable (PullRequestAutomation, PullRequestSummary) async -> Target?
    var head: @Sendable (Target) async -> String? = { _ in nil }
    var isDirty: @Sendable (Target) async -> Bool = { _ in false }
    var collect: Collection = { _, _, _ in nil }
    var reviewComments: @Sendable (PullRequestAutomation, Bool) async throws -> [ReviewComment] = { _, _ in [] }
    var requestBot: @Sendable (PullRequestAutomation, ReviewBot) async throws -> Void = { _, _ in
        // Tests without remote review requests need no implementation.
    }

    let waitReason: @Sendable (Target, String) async -> String?
    var prepare: Preparation = { _, _, candidate in
        candidate.text
    }

    var deliver: @Sendable (AutofixAttempt, String) async throws -> Void
    let result: @Sendable (AutofixAttempt) async throws -> AutofixResult?
    let push: @Sendable (Target, PullRequestSummary, String) async throws -> String
    let resolve: @Sendable (PullRequestAutomation, String) async throws -> Void
}

// MARK: - AutofixContext

struct AutofixContext {
    let key: String
    let store: MetadataStore
    let driver: AutofixDriver
}
