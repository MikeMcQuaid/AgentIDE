import AgentIDEDomain
import Foundation
import TerminalUI

public extension DashboardModel {
    /// Lists a directory of your own under the repository whose menu
    /// asked for it, and shows it at once.
    func addHostDirectory(_ path: String, to repository: Repository) async {
        service.addHostDirectory(path, to: repository)
        await refresh()
    }

    /// Puts a directory of your own on its default branch and
    /// brings it level with origin, which is what most of them are
    /// for between pieces of work.
    func checkoutAndPullDefault(_ item: WorktreeItem) async {
        do {
            try await service.checkoutAndPullDefault(
                worktreePath: item.worktree.path,
                repository: Repository(
                    name: item.worktree.repositoryName,
                    path: item.worktree.path,
                ),
            )
            ErrorLog.shared.note("Checked out and pulled the default branch in \(item.worktree.path).")
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Fetches a directory of your own; its own remotes, not the
    /// repository it is listed under.
    func fetchHostDirectory(_ item: WorktreeItem) async {
        do {
            try await service.fetch(repository: Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.path,
            ))
            ErrorLog.shared.note("Fetched \(item.worktree.path).")
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
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
