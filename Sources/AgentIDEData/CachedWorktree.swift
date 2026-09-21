// MARK: - CachedWorktree

/// A worktree in the sidebar snapshot rendered before the first poll.
public struct CachedWorktree: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates an empty entry.
    public init() {
        // Every property has a default.
    }

    // MARK: Public

    /// The branch checked out in the worktree.
    public var branch = ""

    /// The worktree's canonical path.
    public var path = ""

    /// Whether it is a directory of your own rather than a worktree.
    public var isHostDirectory = false

    /// What the row said last time: uncommitted work, the commit
    /// counts, and whether a session was running in it, so the pane
    /// knows to wait for herdr rather than showing conversations.
    public var isDirty = false
    public var aheadOfUpstream: Int?
    public var aheadOfDefault: Int?
    public var behindDefault: Int?
    public var behindUpstream: Int?
    public var lastActivityAt = 0
    public var hasSession = false

    /// The stack the row's worktree held at the last reading: its
    /// base, its branches bottom first and which was checked out.
    /// Deriving one is a hundred git calls across a wide sidebar,
    /// and every launch was doing all of them in its first second.
    public var stackBase: String?
    public var stackBranches: [String] = []
    public var stackCheckedOut: String?
}
