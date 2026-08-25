import AgentIDEData
import AgentIDEDomain
import Foundation

/// The sidebar the last run left behind: written on every
/// reading and painted before the first one, so the window opens
/// on its own rows and its own selection rather than on an empty
/// frame. Only what herdr owns arrives late.
extension DashboardModel {
    /// Paints the remembered sidebar, selection included.
    func restoreCachedSidebar() {
        let cached = store.load().cachedSidebar
        groups = cached.map { cached in
            let repository = Repository(name: cached.name, path: cached.path, fullName: cached.fullName)
            let items = cached.worktrees.map { worktree in
                WorktreeItem(
                    worktree: Worktree(
                        repositoryName: cached.name,
                        repositoryPath: cached.path,
                        branch: worktree.branch,
                        path: worktree.path,
                        isHostDirectory: worktree.isHostDirectory,
                    ),
                    session: nil,
                    isDirty: worktree.isDirty,
                    aheadOfUpstream: worktree.aheadOfUpstream,
                    hasUnread: false,
                    aheadOfDefault: worktree.aheadOfDefault,
                    behindDefault: worktree.behindDefault,
                    lastActivityAt: worktree.lastActivityAt,
                )
            }
            return RepositoryGroup(repository: repository, items: items, defaultBranch: cached.defaultBranch)
        }
        awaitedSessions = Set(
            cached.flatMap(\.worktrees).filter(\.hasSession).map(\.path),
        )
        if groups.isEmpty == false {
            hasLoaded = true
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = groups.flatMap(\.items).first { $0.worktree.path == stored }
            hasRestoredSelection = selection != nil
        }
    }

    func cacheSidebar(_ groups: [RepositoryGroup]) {
        var metadata = store.load()
        metadata.cachedSidebar = groups.map { group in
            var cached = CachedRepository()
            cached.name = group.repository.name
            cached.fullName = group.repository.fullName
            cached.path = group.repository.path
            cached.defaultBranch = group.defaultBranch
            cached.worktrees = group.items.map { item in
                var worktree = CachedWorktree()
                worktree.branch = item.worktree.branch
                worktree.path = item.worktree.path
                worktree.isHostDirectory = item.worktree.isHostDirectory
                worktree.isDirty = item.isDirty
                worktree.aheadOfUpstream = item.aheadOfUpstream
                worktree.aheadOfDefault = item.aheadOfDefault
                worktree.behindDefault = item.behindDefault
                worktree.lastActivityAt = item.lastActivityAt
                worktree.hasSession = item.session != nil
                return worktree
            }
            return cached
        }
        store.save(metadata)
    }
}
