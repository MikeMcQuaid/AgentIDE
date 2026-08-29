import AgentIDEDomain
import Foundation

// MARK: - SidebarReading

/// What one reading of the system already has in hand, travelling
/// together to every row rather than as three parameters each.
public struct SidebarReading: Sendable {
    let panes: [HerdrPane]
    let activity: [String: Date]
    let metadata: AppMetadata
}

/// The sidebar's reading of the system: every repository's worktrees
/// joined with their sessions. Read in parallel at every level, since
/// each worktree is a handful of git processes sharing nothing.
public extension SessionService {
    /// The full dashboard state: every repository's worktrees joined
    /// with their sessions, plus foreign sessions.
    /// `scope` says whose git is read this time; the others come
    /// back as `kept` gave them, with their sessions brought up to
    /// date from the pane listing.
    func overview(
        scope: GitReadScope = .all,
        kept: [RepositoryGroup] = [],
    ) async -> (groups: [RepositoryGroup], foreign: [AgentSession]) {
        let panes = await (try? herdr.panes()) ?? []
        let activity = spool.activity()
        let metadata = store.load()
        let keptByPath = Dictionary(kept.map { ($0.repository.path, $0) }) { first, _ in first }
        // Every repository is read at once, and every worktree within
        // one at once: each is a handful of git processes that share
        // nothing, and read one after another they were the seconds a
        // wide sidebar took to refresh. The order is put back after.
        let repositories = repositories()
        var groups = await withTaskGroup(of: (Int, RepositoryGroup).self) { tasks in
            for (index, repository) in repositories.enumerated() {
                // A repository not due keeps its last group, with only
                // the live session state, which is a pane listing
                // already in hand, brought up to date.
                if scope.includes(repository.path) == false, let previous = keptByPath[repository.path] {
                    tasks.addTask { (index, Self.refreshingSessions(of: previous, panes: panes)) }
                    continue
                }
                tasks.addTask {
                    await (index, group(
                        of: repository,
                        panes: panes,
                        activity: activity,
                        metadata: metadata,
                    ))
                }
            }
            var collected = [(Int, RepositoryGroup)]()
            for await result in tasks {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // Repositories order by their worktrees' activity; the main
        // checkout's own churn deliberately does not count, except
        // while a session runs there, so resuming on the repository
        // page bumps its repository to the top like a worktree does.
        groups.sort { first, second in
            let firstActive = Self.hasActiveWork(of: first)
            let secondActive = Self.hasActiveWork(of: second)
            guard firstActive == secondActive else {
                return firstActive
            }

            let firstActivity = Self.repositoryActivity(of: first)
            let secondActivity = Self.repositoryActivity(of: second)
            return firstActivity == secondActivity
                ? first.repository.name < second.repository.name
                : firstActivity > secondActivity
        }
        let foreign = panes
            .filter { SessionName.isAgentIDE($0.sessionName) == false }
            .map(Self.foreignSession(of:))
        // The poll is the only thing running while a session is, so
        // it is what keeps the conversation copies current; the
        // schedule inside means this costs a dictionary lookup on
        // almost every tick.
        await backUpRunningConversations(groups)
        return (groups, foreign)
    }

    /// A pane AgentIDE did not create, shown rather than hidden.
    static func foreignSession(of pane: HerdrPane) -> AgentSession {
        AgentSession(
            name: pane.sessionName,
            agent: nil,
            status: pane.isFinished ? .finished : .running,
            workingDirectory: pane.currentPath,
            paneID: pane.paneID,
            activity: pane.activity,
        )
    }

    /// Worktrees in the repository's container that its checkout
    /// does not list: an agent can clone a base of its own beside
    /// them and cut worktrees from that, and those deserve rows,
    /// sessions and deletion like any other. Each carries its
    /// owning checkout as its repository path, so branch work and
    /// removal land on the clone that actually holds the branch.
    /// One directory listing per poll is what makes a manual
    /// worktree appear without a restart.
    func strayWorktrees(of repository: Repository) -> [Worktree] {
        let container = worktreeContainer(repository: repository)
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: container)) ?? []
        return names.sorted().compactMap { name in
            let path = container + "/" + name
            guard name.hasPrefix(".") == false,
                  manager.fileExists(atPath: path + "/.git"),
                  let owner = GitClient.owningCheckout(of: path)
            else {
                return nil
            }

            return Worktree(
                repositoryName: repository.name,
                repositoryPath: owner,
                branch: GitClient.headFileBranch(worktreePath: path) ?? name,
                path: path,
            )
        }
    }

    /// The repository's own checkout as a worktree: its branch is
    /// whatever is actually checked out, so a feature branch in the
    /// main checkout still matches its pull request in the listing.
    func mainCheckout(of repository: Repository, baseRef: String?) async -> Worktree {
        await Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: git.currentBranch(worktreePath: repository.path)
                ?? baseRef.map(Self.branchName(fromBaseRef:)) ?? "main",
            path: repository.path,
        )
    }

    /// A kept group with each row's session re-read from the pane
    /// listing: what runs where can change between full readings,
    /// and the listing is free.
    private static func refreshingSessions(of group: RepositoryGroup, panes: [HerdrPane]) -> RepositoryGroup {
        var refreshed = group
        refreshed.items = group.items.map { item in
            let pane = panes.first { pane in
                SessionName.isAgentIDE(pane.sessionName)
                    && (pane.sessionName == item.session?.name || pane.currentPath == item.worktree.path)
            }
            return item.with(session: pane.map { pane in
                AgentSession(
                    name: pane.sessionName,
                    agent: item.session?.agent ?? .claudeCode,
                    status: pane.isFinished ? .finished : .running,
                    workingDirectory: pane.currentPath,
                    paneID: pane.paneID,
                    activity: pane.activity,
                    version: item.session?.version,
                )
            })
        }
        return refreshed
    }

    /// One repository's group: its checkout and every worktree,
    /// each read beside the others.
    func group(
        of repository: Repository,
        panes: [HerdrPane],
        activity: [String: Date],
        metadata: AppMetadata,
    ) async -> RepositoryGroup {
        async let fullName = git.fullName(of: repository)
        async let worktrees = (try? git.worktrees(of: repository)) ?? []
        let baseRef = await git.defaultBaseRef(of: repository)
        // One read for every branch's counts and dates, rather than
        // three processes per worktree.
        let facts = await git.branchFacts(repositoryPath: repository.path, baseRef: baseRef)
        // The main checkout always appears, so repositories show
        // with no worktrees and orphaned conversations stay
        // reachable.
        let mainCheckout = await mainCheckout(of: repository, baseRef: baseRef)
        var seenPaths = Set<String>()
        var candidates = await ([mainCheckout] + worktrees).filter { seenPaths.insert($0.path).inserted }
        candidates += strayWorktrees(of: repository).filter { seenPaths.insert($0.path).inserted }
        let items = await withTaskGroup(of: (Int, WorktreeItem).self) { tasks in
            for (index, worktree) in candidates.enumerated() {
                tasks.addTask {
                    await (index, item(
                        worktree: worktree,
                        baseRef: baseRef,
                        facts: facts[worktree.branch],
                        reading: SidebarReading(panes: panes, activity: activity, metadata: metadata),
                    ))
                }
            }
            var collected = [(Int, WorktreeItem)]()
            for await result in tasks {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // The main checkout stays pinned first; worktrees order by
        // recency of their own work. Directories of your own come
        // last: they have no activity to order by and are not what
        // the sidebar is mostly about.
        var sorted = [items[0]] + items.dropFirst().sorted { first, second in
            guard first.isActive == second.isActive else {
                return first.isActive
            }

            return first.lastActivityAt > second.lastActivityAt
        }
        sorted += await hostItems(of: repository, metadata: metadata)
        return await RepositoryGroup(
            repository: Repository(name: repository.name, path: repository.path, fullName: fullName),
            items: sorted,
            defaultBranch: baseRef.map(Self.branchName(fromBaseRef:)),
        )
    }

    /// Nothing to count against without a base ref.
    private func aheadBehind(of worktree: Worktree, baseRef: String?) async -> (ahead: Int, behind: Int)? {
        guard let baseRef else {
            return nil
        }

        return await git.aheadBehind(worktreePath: worktree.path, baseRef: baseRef)
    }

    /// One worktree's row: its session, unread state and git counts.
    func item(
        worktree: Worktree,
        baseRef: String?,
        facts: BranchFacts?,
        reading: SidebarReading,
    ) async -> WorktreeItem {
        let metadata = reading.metadata
        let activity = reading.activity
        let session = liveSession(of: worktree, reading: reading)
        let past = pastSessions(of: worktree, liveSession: session)

        // Unread is any agent activity since the worktree was last
        // viewed: the event spool and transcript modification count;
        // herdr keeps no output clock, and the spool and transcripts
        // already cover every agent message.
        var lastEvent = Date.distantPast
        if let session, let spooled = activity[session.name] {
            lastEvent = spooled
        }
        if let newest = past.first {
            lastEvent = max(lastEvent, Date(timeIntervalSince1970: TimeInterval(newest.modifiedAt)))
        }
        let seen = metadata.seenAt[worktree.path] ?? session.flatMap { metadata.lastSeen[$0.name] } ?? startedAt
        let unread = metadata.unreadMarks.contains(worktree.path) || lastEvent > seen

        // The counts and the date came with the repository's own
        // read; only uncommitted work is the worktree's to answer,
        // and only a detached head has to be asked the rest.
        async let dirty = git.isDirty(worktreePath: worktree.path)
        var known = facts
        if known == nil {
            known = await detachedFacts(of: worktree, baseRef: baseRef)
        }
        let isDirty = await dirty
        // Work happening right now is `isActive`, never a "now"
        // stamp: stamping the moment in changed every active row on
        // every poll, and an unchanged row is what a tick may skip.
        let lastActivity = max(known?.committedAt ?? 0, Int(lastEvent.timeIntervalSince1970))
        return WorktreeItem(
            worktree: worktree,
            session: session,
            isDirty: isDirty,
            aheadOfUpstream: known?.aheadOfUpstream,
            hasUnread: unread,
            pastSessions: past,
            aheadOfDefault: known?.ahead,
            behindDefault: known?.behind,
            lastActivityAt: lastActivity,
        )
    }

    /// The session running in a worktree, matched by the recorded
    /// session name first: the pane's current path drifts when the
    /// agent changes directory, which made live sessions vanish from
    /// the UI.
    private func liveSession(of worktree: Worktree, reading: SidebarReading) -> AgentSession? {
        let recorded = reading.metadata.sessionsByWorktree[worktree.path]
        let pane = reading.panes.first { pane in
            SessionName.isAgentIDE(pane.sessionName)
                && (pane.sessionName == recorded || pane.currentPath == worktree.path)
        }
        return pane.map { pane in
            AgentSession(
                name: pane.sessionName,
                agent: agentKind(of: pane.sessionName),
                status: pane.isFinished ? .finished : .running,
                workingDirectory: pane.currentPath,
                paneID: pane.paneID,
                activity: pane.activity,
                version: reading.metadata.agentVersions[pane.sessionName],
            )
        }
    }

    /// The same facts for a worktree no branch name covers, which is
    /// one on a detached head: asked of the worktree itself, the way
    /// every worktree used to be.
    private func detachedFacts(of worktree: Worktree, baseRef: String?) async -> BranchFacts {
        async let counts = aheadBehind(of: worktree, baseRef: baseRef)
        async let committedAt = git.lastCommitDate(worktreePath: worktree.path)
        async let aheadOfUpstream = git.aheadOfUpstream(worktreePath: worktree.path)
        return await BranchFacts(
            ahead: counts?.ahead,
            behind: counts?.behind,
            aheadOfUpstream: aheadOfUpstream,
            committedAt: committedAt,
        )
    }
}
