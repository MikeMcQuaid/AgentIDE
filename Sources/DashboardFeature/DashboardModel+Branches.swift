import AgentIDEData
import AgentIDEDomain
import TerminalUI

/// Opening a branch already on origin as a worktree of its own, with
/// no agent: the worktree's pane then offers to start one.
public extension DashboardModel {
    /// Origin's branches a new worktree can check out; see
    /// `SessionService.remoteBranches`.
    func remoteBranches(repository: Repository, fetching: Bool) async -> [RemoteBranch] {
        await service.remoteBranches(repository: repository, fetching: fetching)
    }

    /// Checks the branch out the way a session's creation does: a
    /// placeholder row appears and is selected the instant the pick
    /// lands, narrates the fetch and checkout, and gives way to the
    /// real worktree, which opens only while the placeholder is still
    /// selected. A failure reaches the Messages pane and drops the row.
    func openRemoteBranch(_ branch: String, in repository: Repository) async {
        let pending = insertPlaceholder(in: repository, branch: branch)
        let path = pending.worktree.path
        let progress = LaunchProgress()
        launchProgresses[path] = progress
        openingBranchPaths.insert(path)
        defer {
            launchProgresses[path] = nil
            openingBranchPaths.remove(path)
        }
        progress.begin("Opening `" + branch + "`")
        showsNewSession = false
        reveal(pending)
        do {
            _ = try await service.reporting(to: progress.reporter).openRemoteBranch(branch, repository: repository)
            await refreshUntil(narrating: progress) { $0.contains { Self.isOpened(branch, in: repository, item: $0) } }
            if selection?.worktree.path == path, showsNewSession == false, showsRepositoryFinder == false,
               let opened = groups.flatMap(\.items).first(where: { Self.isOpened(branch, in: repository, item: $0) })
            {
                reveal(opened)
            }
            removePlaceholder(pending)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            let wasSelected = selection?.worktree.path == path
            removePlaceholder(pending)
            if wasSelected {
                selectMainCheckout(of: repository)
            }
        }
    }

    /// Whether a listed row is the real worktree for the branch,
    /// matched by name since git may report its path resolved.
    private static func isOpened(_ branch: String, in repository: Repository, item: WorktreeItem) -> Bool {
        item.isPlaceholder == false && item.worktree.repositoryPath == repository.path && item.worktree.branch == branch
    }
}
