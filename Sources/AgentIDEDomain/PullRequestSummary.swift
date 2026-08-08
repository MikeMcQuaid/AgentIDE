/// The dashboard-relevant state of an open pull request.
public struct PullRequestSummary: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a pull request summary.
    public init(
        number: Int,
        title: String,
        url: String,
        headBranch: String,
        mergeable: String,
        reviewDecision: String,
        checks: String,
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.headBranch = headBranch
        self.mergeable = mergeable
        self.reviewDecision = reviewDecision
        self.checks = checks
    }

    // MARK: Public

    /// The pull request number.
    public let number: Int

    /// The pull request title.
    public let title: String

    /// The pull request's web address.
    public let url: String

    /// The branch the pull request merges from.
    public let headBranch: String

    /// GitHub's mergeability verdict, for example `MERGEABLE`.
    public let mergeable: String

    /// The aggregate review decision, empty when none.
    public let reviewDecision: String

    /// The aggregate check state, for example `SUCCESS` or `FAILURE`.
    public let checks: String

    /// The stable identity, the pull request number.
    public var id: Int {
        number
    }
}
