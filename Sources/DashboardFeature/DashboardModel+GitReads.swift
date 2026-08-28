import AgentIDEDomain
import Foundation

/// When the sidebar asks git about each repository: when the file
/// system says something under it changed, with slow safety re-reads
/// in case an event was lost. Blind cadence read twenty-nine
/// repositories' git for rows that never changed; an idle workspace
/// now reads almost nothing.
extension DashboardModel {
    /// The safety intervals under a running watcher, and the old
    /// time-based cadence for a machine whose watcher could not
    /// start. Seconds.
    static let selectedGitInterval: TimeInterval = 60
    static let idleGitInterval: TimeInterval = 300
    static let unwatchedSelectedInterval: TimeInterval = 0
    static let unwatchedIdleInterval: TimeInterval = 30

    /// The repositories whose git is read this tick: any asked for
    /// by name, any the watcher saw change, and any past its safety
    /// interval. Everything before the first reading lands.
    func gitReadScope(forcing paths: Set<String>) -> GitReadScope {
        guard hasLoaded else {
            for group in groups {
                gitReadAt[group.repository.path] = Date()
            }
            return .all
        }

        let changed = watcher.consumeChangedPaths()
        let watching = watcher.isWatching
        var due = paths
        let selectedRepository = selection?.worktree.repositoryPath
        for group in groups {
            let path = group.repository.path
            let isSelected = path == selectedRepository
            let interval = watching
                ? (isSelected ? Self.selectedGitInterval : Self.idleGitInterval)
                : (isSelected ? Self.unwatchedSelectedInterval : Self.unwatchedIdleInterval)
            let last = gitReadAt[path] ?? .distantPast
            // Both prefix directions: an event trimmed to the
            // repository directory still covers its deeper worktrees.
            let touched = changed.contains { changedPath in
                changedPath.hasPrefix(path) || group.items.contains { item in
                    changedPath.hasPrefix(item.worktree.path)
                        || item.worktree.path.hasPrefix(changedPath)
                }
            }
            if touched || Date().timeIntervalSince(last) >= interval {
                due.insert(path)
            }
        }
        for repository in due {
            gitReadAt[repository] = Date()
        }
        return .only(due)
    }
}
