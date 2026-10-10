import AgentIDEDomain

extension SessionService {
    func localAutofixSummary(_ state: PullRequestAutomation) async -> PullRequestSummary? {
        guard let path = state.localWorktreePath,
              let branch = await git.currentBranch(worktreePath: path),
              let head = await git.commitHash(of: "HEAD", worktreePath: path)
        else {
            return nil
        }

        return PullRequestSummary(
            number: 0,
            title: "Local review",
            url: state.url,
            headBranch: branch,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: state.attempt?.head ?? head,
        )
    }
}
