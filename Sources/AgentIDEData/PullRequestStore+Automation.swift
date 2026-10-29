import AgentIDEDomain

public extension PullRequestStore {
    /// Saves preferences before the dashboard can act on them.
    func updateAutomation(
        repositoryPath: String,
        summary: PullRequestSummary,
        change: (inout PullRequestAutomation) -> Void,
    ) throws {
        let key = PullRequestAutomation.key(for: summary.url)
        try store.updatePersisting { metadata in
            var state = metadata.pullRequestAutomation[key]
                ?? PullRequestAutomation(repositoryPath: repositoryPath, number: summary.number, url: summary.url)
                .applying(metadata.repositoryFeedbackDefaults[repositoryPath])
            let previous = state
            change(&state)
            if state.reviewBot != previous.reviewBot {
                var defaults = metadata.repositoryFeedbackDefaults[repositoryPath] ?? RepositoryFeedbackDefaults()
                defaults.reviewBot = state.reviewBot
                metadata.repositoryFeedbackDefaults[repositoryPath] = defaults
            }
            metadata.pullRequestAutomation[key] = state
        }
    }

    /// Records the displayed conversation locally; resolution verifies GitHub after a push.
    func toggleResolveOnPush(repositoryPath: String, summary: PullRequestSummary, thread: ReviewThread) throws {
        let threadID = thread.resolveID
        let key = PullRequestAutomation.key(for: summary.url)
        if store.load().pullRequestAutomation[key]?.resolutions[threadID] != nil {
            try store.updatePersisting { $0.pullRequestAutomation[key]?.resolutions[threadID] = nil }
            return
        }
        guard summary.state == "OPEN", let head = summary.headCommit, head.isEmpty == false,
              threadID.isEmpty == false, thread.isResolved == false, let latest = thread.comments.last?.id
        else {
            throw SessionServiceError("The pull request is still loading. Try marking this conversation again shortly.")
        }

        try updateAutomation(repositoryPath: repositoryPath, summary: summary) { state in
            state.resolutions[threadID] = PendingThreadResolution(head: head, commentID: latest)
        }
    }

    /// Whether this thread has a cancellable mark, including a claimed request.
    func pendingResolution(repositoryPath: String, threadID: String, number: Int? = nil) -> Bool {
        store.load().pullRequestAutomation.values.contains { state in
            state.repositoryPath == repositoryPath && (number == nil || state.number == number)
                && state.resolutions[threadID] != nil
        }
    }
}
