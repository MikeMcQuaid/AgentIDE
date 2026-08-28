import AgentIDEDomain
import Foundation

/// How often the sidebar asks git about each repository. The
/// selected one every tick; the rest every half minute, keeping
/// their last rows between readings. Twenty-nine repositories at
/// four git calls per worktree every five seconds was most of
/// everything the app did, for rows that never changed.
extension DashboardModel {
    /// How often an idle repository's git is re-read.
    static let idleGitInterval: TimeInterval = 30

    /// The repositories whose git is read this tick: the selected
    /// one, any asked for by name, and any whose last reading is old
    /// enough. Everything before the first reading lands.
    func gitReadScope(forcing paths: Set<String>) -> GitReadScope {
        guard hasLoaded else {
            for group in groups {
                gitReadAt[group.repository.path] = Date()
            }
            return .all
        }

        var due = paths
        if let selected = selection?.worktree.repositoryPath {
            due.insert(selected)
        }
        for group in groups {
            let last = gitReadAt[group.repository.path] ?? .distantPast
            if Date().timeIntervalSince(last) >= Self.idleGitInterval {
                due.insert(group.repository.path)
            }
        }
        for repository in due {
            gitReadAt[repository] = Date()
        }
        return .only(due)
    }
}
