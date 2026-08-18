import AgentIDEDomain
import Foundation

/// Keeping rows that a single reading of the system lost.
public extension DashboardModel {
    /// Every worktree the sidebar lists; a path leaving this set
    /// is a worktree that has really gone, since a row survives a
    /// reading that lost it while its directory is there.
    var worktreePaths: Set<String> {
        Set(groups.flatMap(\.items).map(\.worktree.path))
    }

    /// Puts back the rows the newest reading dropped whose worktree
    /// is still on disk. A reading is never proof a worktree is
    /// gone: its listing can fail, and git hides a worktree from its
    /// own listing for the whole of a rebase. Losing a row closes
    /// the pane it holds open, taking the shell running there with
    /// it, so only a worktree that really went away loses its row.
    static func retainingLostRows(
        of previous: [RepositoryGroup],
        in next: [RepositoryGroup],
    ) -> [RepositoryGroup] {
        var merged = next.map { fresh -> RepositoryGroup in
            guard let old = previous.first(where: { $0.repository.path == fresh.repository.path }) else {
                return fresh
            }

            var items = fresh.items
            let paths = Set(items.map(\.worktree.path))
            for (index, item) in old.items.enumerated()
                where paths.contains(item.worktree.path) == false && stillExists(item.worktree.path) {
                // Back where it was, so a row the reading lost does
                // not jump down the list and back on the next tick.
                items.insert(item, at: min(index, items.count))
            }
            return RepositoryGroup(repository: fresh.repository, items: items, defaultBranch: fresh.defaultBranch)
        }
        let listed = Set(next.map(\.repository.path))
        merged += previous.filter { listed.contains($0.repository.path) == false && stillExists($0.repository.path) }
        return merged
    }

    /// Whether a worktree or repository is still there; its
    /// directory going away is the one proof of deletion, and both
    /// removing a worktree and deleting a repository take it.
    private static func stillExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
