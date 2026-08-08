// MARK: - WorktreeItem

/// One worktree with everything the dashboard shows about it.
public struct WorktreeItem: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a dashboard item.
    public init(worktree: Worktree, session: AgentSession?, isDirty: Bool, aheadOfUpstream: Int?, hasUnread: Bool) {
        self.worktree = worktree
        self.session = session
        self.isDirty = isDirty
        self.aheadOfUpstream = aheadOfUpstream
        self.hasUnread = hasUnread
    }

    // MARK: Public

    /// The worktree itself.
    public let worktree: Worktree

    /// The tmux session running in it, when one exists.
    public let session: AgentSession?

    /// Whether the worktree has uncommitted changes.
    public let isDirty: Bool

    /// Commits not yet pushed to the upstream, nil without one.
    public let aheadOfUpstream: Int?

    /// Whether the session has produced output since last seen.
    public let hasUnread: Bool

    /// The stable identity, the worktree path.
    public var id: String {
        worktree.id
    }
}

// MARK: - RepositoryGroup

/// A repository with its dashboard-ready worktrees.
public struct RepositoryGroup: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a group.
    public init(repository: Repository, items: [WorktreeItem]) {
        self.repository = repository
        self.items = items
    }

    // MARK: Public

    /// The repository.
    public let repository: Repository

    /// Its worktrees in branch order.
    public let items: [WorktreeItem]

    /// The stable identity, the repository's.
    public var id: String {
        repository.id
    }
}
