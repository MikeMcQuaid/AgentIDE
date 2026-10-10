import AgentIDEDomain

public extension SessionService {
    /// Worktree-local loops and PR loops share one ledger with distinct identities.
    func feedbackState(
        repositoryPath: String,
        worktreePath: String?,
        summary: PullRequestSummary?,
    ) -> PullRequestAutomation {
        let url = summary?.url ?? "local:" + (worktreePath ?? repositoryPath)
        let metadata = store.load()
        if let saved = metadata.pullRequestAutomation[PullRequestAutomation.key(for: url)] {
            return saved
        }
        var state = PullRequestAutomation(repositoryPath: repositoryPath, number: summary?.number ?? 0, url: url)
        state.feedbackWorktreePath = worktreePath
        if let worktreePath {
            state.reviewer = metadata.localReviews[worktreePath]?.reviewer
                ?? localReviewer(worktreePath: worktreePath)
        }
        if summary == nil {
            state.localWorktreePath = worktreePath
        }
        return state.applying(metadata.repositoryFeedbackDefaults[repositoryPath])
    }

    /// Reads only the shared in-memory preferences.
    func currentFeedback(_ fallback: PullRequestAutomation) -> PullRequestAutomation {
        let metadata = store.load()
        return metadata.pullRequestAutomation[PullRequestAutomation.key(for: fallback.url)]
            ?? fallback.applying(metadata.repositoryFeedbackDefaults[fallback.repositoryPath])
    }

    /// Persists a user selection before any collector or agent sees it.
    func updateFeedback(_ state: PullRequestAutomation, change: (inout PullRequestAutomation) -> Void) throws {
        try store.updatePersisting { value in
            let key = PullRequestAutomation.key(for: state.url)
            var current = value.pullRequestAutomation[key]
                ?? state.applying(value.repositoryFeedbackDefaults[state.repositoryPath])
            let previous = current
            change(&current)
            value.pullRequestAutomation[key] = current
            if current.reviewer != previous.reviewer || current.reviewBot != previous.reviewBot {
                value.repositoryFeedbackDefaults[current.repositoryPath] = RepositoryFeedbackDefaults(
                    reviewer: current.reviewer, reviewBot: current.reviewBot,
                )
            }
        }
    }

    /// Finds the PR for the checked-out branch using the existing listing cache.
    func feedbackSummary(repositoryPath: String, worktreePath: String) async throws -> PullRequestSummary? {
        guard let branch = await git.currentBranch(worktreePath: worktreePath) else {
            return nil
        }

        return try await pullRequests.listing(repositoryPath: repositoryPath, scope: .branch(branch))
            .first { $0.state == "OPEN" }
    }

    /// An interrupted collection needs an explicit retry, never a hidden rerun.
    func recoverFeedback(_ state: PullRequestAutomation) async throws {
        guard state.collection?.isPending == true,
              await feedbackCollector.isRunning(PullRequestAutomation.key(for: state.url)) == false
        else {
            return
        }

        try updateFeedback(state) { value in
            value.collection?.isPending = false
            value.collection?.failure = "Feedback collection was interrupted. Choose Review to retry."
            value.lastResult = value.collection?.failure ?? ""
            value.pending = ""
            if value.isAutomatic {
                value.loopResult = .failed
            }
            value.isAutomatic = false
        }
    }
}
