import SanductorData
import SanductorDomain
import TerminalUI

extension ReviewModel {
    /// Flips one conversation's resolved state on GitHub, then
    /// refreshes the inline listing.
    func toggleResolved(_ thread: ReviewThread) async {
        do {
            try await setThreadResolved(thread.resolveID, thread.isResolved == false)
            threads = await fetchThreads()
        } catch {
            report(error.localizedDescription)
        }
        hasLoaded = true
    }

    func toggleResolveOnPush(_ thread: ReviewThread) {
        do {
            try resolveOnPush?(thread)
            UtilityTabTarget.resolutionMarksChanged()
        } catch {
            report(error.localizedDescription)
        }
    }

    func configureResolveOnPush(worktree: Worktree, pullRequests: PullRequestStore) {
        resolveOnPush = { [weak self] thread in
            guard let summary = pullRequests.cachedListing(
                repositoryPath: worktree.repositoryPath, scope: .branch(worktree.branch),
            )?
                .first(where: { $0.state == "OPEN" })
            else {
                self?.report("The pull request is still loading. Try marking this conversation again shortly.")
                return
            }

            try pullRequests.toggleResolveOnPush(
                repositoryPath: worktree.repositoryPath,
                summary: pullRequests.cachedSummary(repositoryPath: worktree.repositoryPath, number: summary.number)
                    ?? summary,
                thread: thread,
            )
        }
        pendingResolution = { thread in
            pullRequests.pendingResolution(repositoryPath: worktree.repositoryPath, threadID: thread.resolveID)
        }
    }
}
