import AgentIDEDomain
import Foundation

public extension DashboardModel {
    /// Lists a directory of your own under the repository whose menu
    /// asked for it, and shows it at once.
    func addHostDirectory(_ path: String, to repository: Repository) async {
        service.addHostDirectory(path, to: repository)
        await refresh()
    }

    /// Stops listing one; nothing on disk is touched.
    func forgetHostDirectory(_ item: WorktreeItem) async {
        if selection?.id == item.id {
            selection = nil
        }
        service.forgetHostDirectory(item.worktree.path, from: item.worktree.repositoryPath)
        await refresh()
    }
}
