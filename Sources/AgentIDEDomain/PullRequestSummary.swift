import Foundation

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
        author: String? = nil,
        body: String? = nil,
        unresolvedComments: Int = 0,
        isQueued: Bool = false,
        closedAt: Date? = nil,
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
        self.author = author
        self.body = body
        self.unresolvedComments = unresolvedComments
        self.isQueued = isQueued
        self.closedAt = closedAt
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

    /// The author's GitHub login; optional so summaries cached by
    /// earlier releases still decode.
    public let author: String?

    /// The description, carried from the listing so a click-through
    /// shows the conversation immediately; optional like the author.
    public let body: String?

    /// Whether it is in a merge queue right now. A repository
    /// having a queue, or a pull request being set to merge
    /// automatically, is not the same thing: only this says the
    /// queue is what happens next. Settable, with the conversation
    /// count, because both are stamped onto a fetched summary from
    /// what the app already knows.
    public var isQueued: Bool

    /// When it was merged or closed, nil while open. Branch names
    /// are reused, so a long-finished pull request matching a
    /// branch is a coincidence rather than its work; optional so
    /// summaries cached by earlier releases still decode.
    public let closedAt: Date?

    /// Review conversations still open on it, which the listing
    /// query cannot answer: GitHub only counts them through GraphQL,
    /// so this stays zero until the pull request is looked at and
    /// the count is remembered.
    public var unresolvedComments: Int

    /// Whether the checks rollup is red: something has concluded
    /// failing, even while the rest still runs. Pending and green
    /// rollups say no, which is what greys the failing-logs button
    /// until there is a failure to read.
    public var hasFailingChecks: Bool {
        checks == "FAILURE"
    }

    /// The pull request's checks page.
    public var checksPageURL: String {
        url + "/checks"
    }

    /// Where a click on the check state should go: the one failing
    /// run when there is exactly one, otherwise the checks page.
    public var checksClickURL: String {
        if failingCheckLinks.count == 1 {
            failingCheckLinks[0]
        } else {
            checksPageURL
        }
    }

    /// The stable identity, the pull request number.
    public var id: Int {
        number
    }
}

// MARK: - ReviewComment

/// One human comment on a pull request, from a review or the
/// thread. Codable so conversations can cache between runs.
public struct ReviewComment: Identifiable, Hashable, Sendable, Codable {
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
