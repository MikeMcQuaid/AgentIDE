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
            // A creation placeholder has no directory yet, so it is
            // kept until the work it stands for is listed. The two
            // never share a name, since the creation names the
            // branch itself, so what says the work has landed is the
            // repository gaining a row at all: without this the
            // pending row sat beside its own worktree for the whole
            // of the agent's launch.
            let landed = paths.subtracting(old.items.map(\.worktree.path)).isEmpty == false
            let lost = old.items.enumerated().filter { row in
                guard paths.contains(row.element.worktree.path) == false else {
                    return false
                }
                guard row.element.isPlaceholder else {
                    return stillExists(row.element.worktree.path)
                }

                return landed == false
            }
            for (index, item) in lost {
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
