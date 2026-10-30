import SanductorDomain

public extension SessionService {
    /// Wake the signer while the user is present, before any fix can be delivered.
    func startFeedbackLoop(_ initial: PullRequestAutomation) async throws {
        let state = currentFeedback(initial)
        guard state.isLoopRunning == false, state.collection?.isPending != true else {
            return
        }

        var signingResult = ""
        if AppSettings.requiresSignedCommits {
            try updateFeedback(state) { $0.pending = "Checking commit signing; approve your signer if prompted" }
            do {
                if let summary = try await automationSummary(state, fresh: false),
                   let worktree = try await feedbackWorktree(state, summary: summary),
                   let defaultBranch = await defaultBranchName(of: Repository(name: "", path: state.repositoryPath)),
                   worktree.branch != defaultBranch
                {
                    try await git.warmSigning(worktreePath: worktree.path)
                    signingResult = "Commit signer checked; the branch and uncommitted changes are unchanged"
                }
            } catch {
                signingResult = "Signing warm-up failed; autofix will still try signing when pushing. "
                    + error.localizedDescription
            }
        }
        try updateFeedback(state) { value in
            value.startLoop()
            value.lastResult = signingResult
        }
    }
}
