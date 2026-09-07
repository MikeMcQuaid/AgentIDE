// MARK: - OnDeviceSummarising

/// On-device summarisation for branch names, commit messages and pull
/// request drafts. Mac uses Apple's foundation model; platforms
/// without one inject `NullSummariser`.
public protocol OnDeviceSummarising: Sendable {
    /// A short underscore-separated branch name summarising a
    /// prompt, nil when the model cannot help.
    func branchName(for prompt: String) async -> String?

    /// A commit message drafted from a diff, nil when the model
    /// cannot help.
    func commitMessage(fromDiff diff: String) async -> String?

    /// A pull request title and body drafted from the branch's
    /// commit messages, nil when the model cannot help.
    func pullRequestDescription(
        fromCommits commits: [String],
        branch: String,
    ) async -> (title: String, body: String)?

    /// The repository's pull request template completed from the
    /// branch's commit messages, nil when the model cannot help.
    func filledTemplate(fromCommits commits: [String], template: String) async -> String?
}

// MARK: - NullSummariser

/// A summariser that always answers nil, so callers take their
/// deterministic fallbacks.
public struct NullSummariser: OnDeviceSummarising {
    // MARK: Lifecycle

    public init() {
        // Always answers nil.
    }

    // MARK: Public

    public func branchName(for _: String) -> String? {
        nil
    }

    public func commitMessage(fromDiff _: String) -> String? {
        nil
    }

    public func pullRequestDescription(
        fromCommits _: [String],
        branch _: String,
    ) -> (title: String, body: String)? {
        nil
    }

    public func filledTemplate(fromCommits _: [String], template _: String) -> String? {
        nil
    }
}
