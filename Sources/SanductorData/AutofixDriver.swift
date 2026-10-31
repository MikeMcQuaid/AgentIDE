import SanductorDomain

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
    let writers: @Sendable (PullRequestAutomation, Set<String>, Bool) async -> Set<String>
    var localReview: @Sendable (PullRequestAutomation) async throws -> LocalReview? = { _ in nil }
    let target: @Sendable (PullRequestAutomation, PullRequestSummary) async -> Target?
    var head: @Sendable (Target) async -> String? = { _ in nil }
    var sameTree: @Sendable (Target, String, String) async -> Bool = { _, lhs, rhs in lhs == rhs }
    var revision: @Sendable (Target) async throws -> String = { _ in "" }
    var isDirty: @Sendable (Target) async -> Bool = { _ in false }
    var collect: Collection = { _, _, _ in nil }
    var reviewComments: @Sendable (PullRequestAutomation, Bool) async throws -> [ReviewComment] = { _, _ in [] }
    var conflictBase: @Sendable (Target, PullRequestSummary) async throws -> String? = { _, _ in nil }
    var containsHead: @Sendable (Target, String) async -> Bool = { _, _ in false }

    var containsFix: @Sendable (PullRequestAutomation, String, String) async -> Bool = { _, commit, head in
        commit == head
    }

    let waitReason: @Sendable (Target, String) async -> String?
    var prepare: Preparation = { _, _, candidate in
        candidate.text
    }

    var deliver: @Sendable (AutofixAttempt, String) async throws -> Void
    let result: @Sendable (AutofixAttempt) async throws -> AutofixResult?
    let resolve: @Sendable (PullRequestAutomation, String) async throws -> Void
}

// MARK: - AutofixContext

struct AutofixContext {
    let key: String
    let store: MetadataStore
    let driver: AutofixDriver
}
