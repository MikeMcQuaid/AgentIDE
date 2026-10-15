/// A branch on origin, enough to pick one to check out as a new
/// worktree.
public struct RemoteBranch: ReferencedItem, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a branch.
    public init(name: String) {
        self.name = name
    }

    // MARK: Public

    /// A branch is all name: git owns it, so pickers show it in the
    /// style kept for git's names.
    public static let isGitName = true

    /// The branch name, without the remote.
    public let name: String

    /// The stable identity, the branch name.
    public var id: String {
        name
    }

    /// The name, which is what the picker searches.
    public var reference: String {
        name
    }

    /// Nothing beyond the name.
    public var title: String {
        ""
    }
}
