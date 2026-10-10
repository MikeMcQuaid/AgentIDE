import AgentIDEDomain

extension SessionService {
    func localAutofixSummary(_ state: PullRequestAutomation, fresh: Bool) async throws -> PullRequestSummary? {
        guard let path = state.localWorktreePath,
              let branch = await git.currentBranch(worktreePath: path),
              let head = await git.commitHash(of: "HEAD", worktreePath: path)
        else {
            return nil
        }

        let listed = try? await pullRequests.listing(repositoryPath: state.repositoryPath, scope: .branch(branch))
        if let open = listed?.first(where: { $0.state == "OPEN" }),
           let summary = try await (fresh
               ? github.pullRequestSummary(repositoryPath: state.repositoryPath, number: open.number)
               : pullRequests.summary(repositoryPath: state.repositoryPath, number: open.number))
        {
            if state.isAutomatic, state.attempt == nil {
                try updateFeedback(state) { value in
                    value.isAutomatic = false
                    value.pending = ""
                    value.lastResult = "A PR now exists; enable autofix separately in its feedback controls"
                }
                return nil
            }
            if summary.headCommit == (state.attempt?.remoteHead ?? head) {
                return summary
            }
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
