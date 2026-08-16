import AgentIDEData
import AgentIDEDomain
import TerminalUI

/// Cleanup after a merge, split from the model body for length: the
/// one merge-safe path behind the Merge button, the context menu and
/// the poll's own merge detection.
public extension DashboardModel {
    /// Tidies a worktree whose pull request has merged, merge-safely:
    /// a real worktree is removed only when it is clean and its branch
    /// is fully on the base branch (git's `-d` rule), otherwise the
    /// refusal comes back for the caller to show; the main checkout is
    /// returned to the default branch with the merged branch safely
    /// deleted. The one path behind the Merge button, the context menu
    /// and the poll's own merge detection: nothing here can lose
    /// work, and only the explicit, confirmed Delete worktree forces.
    @discardableResult
    func cleanUp(item: WorktreeItem) async -> SessionService.CleanupRefusal? {
        if item.worktree.path == item.worktree.repositoryPath {
            await service.cleanUpAfterMerge(worktree: item.worktree, mergedBranch: item.worktree.branch)
            await refresh()
            return nil
        }

        guard let baseRef = baseRef(for: item) else {
            ErrorLog.shared.report(
                "Cannot tell whether \(item.worktree.branch) is merged: the repository has no default branch",
            )
            return .unmerged
        }

        deletingPaths.insert(item.worktree.path)
        defer { deletingPaths.remove(item.worktree.path) }
        do {
            let refusal = try await service.cleanUpMergedWorktree(item: item, baseRef: baseRef)
            if refusal == nil {
                if selection?.id == item.id {
                    selection = nil
                }
                await refresh()
            }
            return refusal
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return .unmerged
        }
    }

    /// The remote default branch ref a worktree's branch merges into,
    /// nil when the repository's default is unknown.
    func baseRef(for item: WorktreeItem) -> String? {
        groups.first { $0.repository.path == item.worktree.repositoryPath }?
            .defaultBranch
            .map { "origin/" + $0 }
    }

    /// Whether a main checkout sits on a branch other than its
    /// repository's default, the only state in which cleaning it up
    /// after a merge means anything; false when the default is
    /// unknown, so the offer never appears on a guess.
    func isOffDefaultBranch(_ item: WorktreeItem) -> Bool {
        guard item.worktree.path == item.worktree.repositoryPath,
              let group = groups.first(where: { $0.repository.path == item.worktree.repositoryPath }),
              let defaultBranch = group.defaultBranch
        else {
            return false
        }

        return item.worktree.branch != defaultBranch
    }
}
