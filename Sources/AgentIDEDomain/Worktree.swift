/// A git worktree belonging to a repository, holding one branch.
public struct Worktree: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a worktree record.
    public init(repositoryName: String, repositoryPath: String, branch: String, path: String) {
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.path = path
    }

    // MARK: Public

    /// The owning repository's name.
    public let repositoryName: String

    /// The owning repository's checkout path.
    public let repositoryPath: String

    /// The branch checked out in this worktree.
    public let branch: String

    /// The worktree's canonical path.
    public let path: String

    /// The stable identity, the worktree path.
    public var id: String {
        path
    }
}
