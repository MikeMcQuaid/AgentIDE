// MARK: - PullRequestSummary

/// The dashboard-relevant state of an open pull request. Codable so
/// the dashboard can cache it between runs.
public struct PullRequestSummary: Identifiable, Hashable, Sendable, Codable {
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
        failingCheckLinks: [String] = [],
        baseBranch: String = "",
        state: String = "OPEN",
        isDraft: Bool = false,
        hasAutomerge: Bool = false,
        headOID: String = "",
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.headBranch = headBranch
        self.mergeable = mergeable
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.failingCheckLinks = failingCheckLinks
        self.baseBranch = baseBranch
        self.state = state
        self.isDraft = isDraft
        self.hasAutomerge = hasAutomerge
        self.headOID = headOID
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

    /// Detail pages of failing check runs, empty when green.
    public let failingCheckLinks: [String]

    /// The branch the pull request merges into.
    public let baseBranch: String

    /// GitHub's state: `OPEN`, `MERGED` or `CLOSED`.
    public let state: String

    /// Whether the pull request is a draft.
    public let isDraft: Bool

    /// Whether automerge is enabled.
    public let hasAutomerge: Bool

    /// The head commit the states describe; green results for a
    /// commit are treated as final, so caches key on it.
    public let headOID: String

    /// The pull request's checks page.
    public var checksPageURL: String {
        url + "/checks"
    }

    /// Where a click on the check state should go: the one failing
    /// run when there is exactly one, otherwise the checks page.
    public var checksClickURL: String {
        failingCheckLinks.count == 1 ? failingCheckLinks[0] : checksPageURL
    }

    /// The stable identity, the pull request number.
    public var id: Int {
        number
    }
}

// MARK: - ReviewComment

/// One human comment on a pull request, from a review or the thread.
public struct ReviewComment: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a comment.
    public init(id: Int, author: String, body: String, kind: String = "") {
        self.id = id
        self.author = author
        self.body = body
        self.kind = kind
    }

    // MARK: Public

    /// The comment's position in the fetched list.
    public let id: Int

    /// The GitHub login of the author.
    public let author: String

    /// The comment text.
    public let body: String

    /// The review state that produced this entry, such as
    /// `APPROVED`; empty for plain comments.
    public let kind: String
}

// MARK: - SearchHit

/// One match from a worktree search.
public struct SearchHit: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a search hit.
    public init(file: String, line: Int, text: String) {
        self.file = file
        self.line = line
        self.text = text
    }

    // MARK: Public

    /// The matching file, relative to the worktree.
    public let file: String

    /// The one-based matching line.
    public let line: Int

    /// The matching line's text.
    public let text: String

    /// The stable identity within one result set.
    public var id: String {
        file + ":" + String(line)
    }
}
