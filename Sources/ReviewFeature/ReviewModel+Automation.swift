import AgentIDEData
import AgentIDEDomain
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

    func toggleResolveOnPush(_ thread: ReviewThread) async {
        do {
            try await resolveOnPush?(thread)
        } catch {
            report(error.localizedDescription)
        }
    }

    func configureResolveOnPush(worktree: Worktree, git: GitClient, pullRequests: PullRequestStore) {
        resolveOnPush = { thread in
            let branch = await git.currentBranch(worktreePath: worktree.path) ?? worktree.branch
            let listed = try await pullRequests.listing(
                repositoryPath: worktree.repositoryPath,
                scope: .branch(branch),
            )
            guard let number = listed.first(where: { $0.state == "OPEN" })?.number else {
                return
            }

            try await pullRequests.toggleResolveOnPush(
                repositoryPath: worktree.repositoryPath, number: number, threadID: thread.resolveID,
            )
            UtilityTabTarget.pullRequestCacheChanged()
        }
        pendingResolution = { thread in
            pullRequests.pendingResolution(repositoryPath: worktree.repositoryPath, threadID: thread.resolveID)
        }
    }
}
