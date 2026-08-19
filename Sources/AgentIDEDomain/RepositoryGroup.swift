// MARK: - WorktreeItem

/// One worktree with everything the dashboard shows about it.
public struct WorktreeItem: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a dashboard item.
    public init(
        worktree: Worktree,
        session: AgentSession?,
        isDirty: Bool,
        aheadOfUpstream: Int?,
        hasUnread: Bool,
        pastSessions: [TranscriptSession] = [],
        aheadOfDefault: Int? = nil,
        behindDefault: Int? = nil,
        lastActivityAt: Int = 0,
    ) {
        self.worktree = worktree
        self.session = session
        self.pastSessions = pastSessions
        self.isDirty = isDirty
        self.aheadOfUpstream = aheadOfUpstream
        self.aheadOfDefault = aheadOfDefault
        self.behindDefault = behindDefault
        self.hasUnread = hasUnread
        self.lastActivityAt = lastActivityAt
    }

    // MARK: Public

    /// The worktree itself.
    public let worktree: Worktree

    /// The tmux session running in it, when one exists.
    public let session: AgentSession?

    /// Earlier conversations discovered from transcripts, newest
    /// first, excluding the live session's own transcript.
    public let pastSessions: [TranscriptSession]

    /// Whether the worktree has uncommitted changes.
    public let isDirty: Bool

    /// Commits not yet pushed to the upstream, nil without one.
    public let aheadOfUpstream: Int?

    /// Commits on this branch missing from the default branch.
    public let aheadOfDefault: Int?

    /// Commits on the default branch missing from this branch.
    public let behindDefault: Int?

    /// Whether the session has produced output since last seen.
    public var hasUnread: Bool

    /// When the worktree last saw work: a commit, agent output, a
    /// running session or uncommitted edits. Seconds since 1970.
    public let lastActivityAt: Int

    /// The stable identity, the worktree path.
    public var id: String {
        worktree.id
    }

    /// The same row with no session running in it, for a close that
    /// should show on screen before tmux has been asked again.
    public func withoutSession() -> Self {
        Self(
            worktree: worktree,
            session: nil,
            isDirty: isDirty,
            aheadOfUpstream: aheadOfUpstream,
            hasUnread: hasUnread,
            pastSessions: pastSessions,
            aheadOfDefault: aheadOfDefault,
            behindDefault: behindDefault,
            lastActivityAt: lastActivityAt,
        )
    }
}

// MARK: - RepositoryGroup

/// A repository with its dashboard-ready worktrees.
public struct RepositoryGroup: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a group; `defaultBranch` is nil when the repository
    /// has no resolvable default (never pushed, no `main`).
    public init(repository: Repository, items: [WorktreeItem], defaultBranch: String? = nil) {
        self.repository = repository
        self.items = items
        self.defaultBranch = defaultBranch
    }

    // MARK: Public

    /// The repository.
    public let repository: Repository

    /// Its worktrees in branch order.
    public var items: [WorktreeItem]

    /// The bare default branch name (`main`, never `origin/main`),
    /// so the sidebar can tell a main checkout off its default branch
    /// without asking git.
    public let defaultBranch: String?

    /// The stable identity, the repository's.
    public var id: String {
        repository.id
    }
}
