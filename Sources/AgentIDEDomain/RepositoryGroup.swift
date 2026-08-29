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

    /// The agent session running in it, when one exists.
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

    /// Whether work is happening right now: a session with the run
    /// light on, or a session whose worktree holds uncommitted
    /// edits. Ordering reads this beside `lastActivityAt` rather
    /// than the moment being stamped into it: a "now" timestamp
    /// changed every active row on every poll, and row equality is
    /// what lets a tick redraw nothing.
    public var isActive: Bool {
        session != nil && (session?.status == .running || isDirty)
    }

    /// Whether unread output is worth acting on: the turn is done,
    /// the process ended, or the agent is blocked on input. Output
    /// still streaming from a working agent is not news, and the
    /// dot that lit for it kept lighting with nothing to do.
    public var hasActionableUnread: Bool {
        guard hasUnread else {
            return false
        }
        guard let session else {
            return true
        }

        return session.status == .finished
            || session.activity == .done
            || session.activity == .blocked
    }

    /// The stable identity, the worktree path.
    public var id: String {
        worktree.id
    }

    /// The same row with its session re-read: what runs where is a
    /// pane listing already in hand, where the rest of the row is
    /// git the idle repository was not asked again.
    public func with(session: AgentSession?) -> Self {
        Self(
            worktree: worktree,
            session: session,
            isDirty: isDirty,
            aheadOfUpstream: aheadOfUpstream,
            hasUnread: hasUnread,
            pastSessions: pastSessions,
            aheadOfDefault: aheadOfDefault,
            behindDefault: behindDefault,
            lastActivityAt: lastActivityAt,
        )
    }

    /// The same row on a different branch, for a checkout that has
    /// just moved: the sidebar says so before the next full reading
    /// comes back.
    public func renamed(branch: String) -> Self {
        Self(
            worktree: Worktree(
                repositoryName: worktree.repositoryName,
                repositoryPath: worktree.repositoryPath,
                branch: branch,
                path: worktree.path,
                isHostDirectory: worktree.isHostDirectory,
            ),
            session: session,
            isDirty: isDirty,
            aheadOfUpstream: aheadOfUpstream,
            hasUnread: hasUnread,
            pastSessions: pastSessions,
            aheadOfDefault: aheadOfDefault,
            behindDefault: behindDefault,
            lastActivityAt: lastActivityAt,
        )
    }

    /// The same row with no session running in it, for a close that
    /// should show on screen before herdr has been asked again.
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

public extension [RepositoryGroup] {
    /// The group an item belongs to: by membership first, since an
    /// adopted worktree's repository path names the clone that owns
    /// its branch, which no group is keyed by. Falling back to the
    /// repository path covers items from readings these groups have
    /// not caught up with yet.
    func group(holding item: WorktreeItem) -> RepositoryGroup? {
        first { group in group.items.contains { $0.worktree.path == item.worktree.path } }
            ?? first { $0.repository.path == item.worktree.repositoryPath }
    }
}
