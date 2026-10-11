/// A repository in the sidebar snapshot rendered before the first
/// poll.
public struct CachedRepository: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates an empty entry.
    public init() {
        // Every property has a default.
    }

    // MARK: Public

    /// The repository's directory name.
    public var name = ""

    /// The GitHub `owner/name`, when known.
    public var fullName: String?

    /// The repository's default branch, when known.
    public var defaultBranch: String?

    /// The checkout path.
    public var path = ""

    /// The repository's worktrees.
    public var worktrees: [CachedWorktree] = []
}
