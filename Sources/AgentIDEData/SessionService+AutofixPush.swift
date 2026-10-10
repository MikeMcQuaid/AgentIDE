import AgentIDEDomain
import Foundation

extension SessionService {
    /// Both CI and review fixes push only the reported commit to the existing PR.
    func pushAutofix(target: AutofixDriver.Target, summary: PullRequestSummary, commit: String) async throws -> String {
        let worktree = target.worktree
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        guard let defaultBranch = await defaultBranchName(of: repository), worktree.branch != defaultBranch,
              summary.headBranch == worktree.branch, let head = summary.headCommit, head != commit,
              let headRepository = summary.headRepository,
              await automationWaitReason(target: target, head: commit) == nil,
              await git.isDirty(worktreePath: worktree.path) == false,
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
            try await git.rebaseSigned(worktreePath: worktree.path, branch: worktree.branch, onto: head)
        }
        guard let pushed = await git.commitHash(of: "HEAD", worktreePath: worktree.path), pushed != head,
              let tree = await git.commitHash(of: commit + "^{tree}", worktreePath: worktree.path),
              await git.commitHash(of: pushed + "^{tree}", worktreePath: worktree.path) == tree,
              await git.isAncestor(head, of: pushed, worktreePath: worktree.path),
              await git.isDirty(worktreePath: worktree.path) == false,
              await automationWaitReason(target: target, head: pushed) == nil
        else {
            throw SessionServiceError("The autofix changed during signing; inspect the changes before pushing")
        }

        if AppSettings.requiresSignedCommits,
           await git.allCommitsSigned(worktreePath: worktree.path, range: head + ".." + pushed) == false
        {
            throw SessionServiceError("Autofix signing failed; inspect the changes before pushing")
        }
        try await git.push(
            worktreePath: worktree.path,
            branch: worktree.branch,
            remote: remote,
            expectedTip: head,
            sourceCommit: pushed,
        )
        pullRequests.invalidate(repositoryPath: worktree.repositoryPath, number: summary.number)
        pullRequests.invalidateListings(repositoryPath: worktree.repositoryPath)
        return pushed
    }
}
