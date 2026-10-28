// MARK: - PushDestination

/// Where a branch can be pushed: the repository it came from, or the
/// viewer's own fork of it when they may not write there.
public enum PushDestination: Hashable, Sendable {
    case origin
    case fork(owner: String)

    /// The fork a checked-out pull request came from, which git
    /// already holds the URL for: pushing there is what updates the
    /// pull request, and pushing to origin would open a branch in
    /// the repository it was opened against instead.
    case contributorFork(owner: String, remote: String)

    // MARK: Public

    /// The remote a push goes to: a fork's is named after its owner,
    /// which is what `gh repo fork` and the naming of a contributor's
    /// fork both do.
    public var remote: String {
        switch self {
        case .origin:
            "origin"

        case let .fork(owner):
            owner

        case let .contributorFork(_, remote):
            remote
        }
    }

    /// How `gh pr create` must name the branch: `owner:branch` when
    /// it lives in a fork, since the pull request belongs to the
    /// repository it is opened against rather than the one holding
    /// the branch, and the plain name otherwise. Never nil: left to
    /// itself `gh` opens a pull request for whatever is checked out,
    /// which in a stack of branches in one worktree is rarely the
    /// branch being looked at.
    public func head(branch: String) -> String {
        switch self {
        case .origin:
            branch

        case let .contributorFork(owner, _),
             let .fork(owner):
            owner + ":" + branch
        }
    }
}

// MARK: - MergeCleanupReport

/// What a post-merge cleanup did and what it could not do, so the
/// caller can put both in the messages pane rather than the work
/// happening silently.
public struct MergeCleanupReport: Sendable {
    // MARK: Lifecycle

    /// Creates an empty report.
    public init() {
        // Both lists fill as the cleanup runs.
    }

    // MARK: Public

    /// What the cleanup did, in order.
    public var notes: [String] = []

    /// What it could not do, each naming the step and the reason.
    public var failures: [String] = []
}
