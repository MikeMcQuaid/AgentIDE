import AgentIDEDomain
import Foundation

extension SessionService {
    /// Both CI and review fixes push only the reported commit to the existing PR.
    func pushAutofix(target: AutofixDriver.Target, summary: PullRequestSummary, commit: String) async throws {
        let worktree = target.worktree
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        guard let defaultBranch = await defaultBranchName(of: repository), worktree.branch != defaultBranch,
              summary.headBranch == worktree.branch, let head = summary.headCommit, head != commit,
              let headRepository = summary.headRepository,
              await automationReady(target: target, head: commit),
              await git.isAncestor(head, of: commit, worktreePath: worktree.path)
        else {
            throw SessionServiceError("The autofix branch or commit changed; push the reviewed changes manually")
        }

        let destination = await pushDestination(worktree: worktree)
        guard let remote = await git.remoteURL(named: destination.remote, worktreePath: worktree.path, forPush: true),
              URL(string: remote)?.host == "github.com" || remote.hasPrefix("git@github.com:"),
              GitHubRemote.fullName(ofURL: remote)?.lowercased() == headRepository.lowercased()
        else {
            throw SessionServiceError("The push remote does not match this pull request's head repository")
        }

        if AppSettings.requiresSignedCommits,
           await git.allCommitsSigned(worktreePath: worktree.path, range: head + ".." + commit) == false
        {
            throw SessionServiceError("Autofix commits must be signed before pushing")
        }
        try await git.push(
            worktreePath: worktree.path,
            branch: worktree.branch,
            remote: remote,
            expectedTip: head,
            sourceCommit: commit,
        )
        pullRequests.invalidate(repositoryPath: worktree.repositoryPath, number: summary.number)
        pullRequests.invalidateListings(repositoryPath: worktree.repositoryPath)
    }
}
