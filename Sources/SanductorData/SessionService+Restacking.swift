import Foundation
import SanductorDomain

extension SessionService {
    func stackBranchIsReady(_ branch: String, parent: String, worktreePath: String) async -> Bool {
        guard await git.isAncestor(parent, of: branch, worktreePath: worktreePath) else {
            return false
        }
        guard AppSettings.requiresSignedCommits else {
            return true
        }

        return await git.isCommitSigned(worktreePath: worktreePath, ref: branch)
    }

    func stackBaseRef(in stack: BranchStack, worktreePath: String) async -> String? {
        guard let base = stack.base else {
            return nil
        }

        let remote = "refs/remotes/origin/" + base
        return await git.refExists(worktreePath: worktreePath, ref: remote) ? remote : base
    }

    /// Only the bottom layer may retry against a refreshed remote base.
    func rebaseStackBranch(
        branch: String,
        onto parent: String,
        from oldBase: String,
        fallback: String?,
        worktreePath: String,
    ) async throws {
        let originalTip = await git.tip(of: branch, worktreePath: worktreePath)
        do {
            try await git.rebaseSigned(branch: branch, onto: parent, from: oldBase, worktreePath: worktreePath)
        } catch {
            guard let fallback, let originalTip, Task.isCancelled == false,
                  await git.refExists(worktreePath: worktreePath, ref: fallback)
            else {
                throw error
            }

            let firstFailure = error.localizedDescription
            do {
                try await git.fetch(repositoryPath: worktreePath)
                rememberFetch(repositoryPath: GitClient.owningCheckout(of: worktreePath) ?? worktreePath)
            } catch {
                throw SessionServiceError(
                    firstFailure + "\nRefreshing the rebase base failed: " + error.localizedDescription,
                )
            }
            guard Task.isCancelled == false,
                  let remoteTip = await git.tip(of: fallback, worktreePath: worktreePath), remoteTip != oldBase,
                  await git.isAncestor(oldBase, of: remoteTip, worktreePath: worktreePath),
                  await git.currentBranch(worktreePath: worktreePath) == branch,
                  await git.tip(of: branch, worktreePath: worktreePath) == originalTip,
                  await git.isDirty(worktreePath: worktreePath) == false
            else {
                throw error
            }

            PerformanceLog.recordMessage(firstFailure + "\nRetrying against " + fallback, isError: false)
            do {
                try await git.rebaseSigned(
                    branch: branch,
                    onto: remoteTip,
                    from: remoteTip,
                    worktreePath: worktreePath,
                )
            } catch {
                throw SessionServiceError(
                    firstFailure + "\nRebase onto " + fallback + " failed: " + error.localizedDescription,
                )
            }
        }
    }
}
