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

    /// Marks fresh GitHub state, never a cached head predating an unseen push.
    func toggleResolveOnPush(repositoryPath: String, number: Int, threadID: String) async throws {
        if let entry = store.load().pullRequestAutomation.first(where: { entry in
            entry.value.repositoryPath == repositoryPath && entry.value.number == number
        }), entry.value.resolutions[threadID] != nil {
            try store.updatePersisting { $0.pullRequestAutomation[entry.key]?.resolutions[threadID] = nil }
            return
        }
        guard let summary = try await github.pullRequestSummary(repositoryPath: repositoryPath, number: number),
              summary.state == "OPEN", let head = summary.headCommit,
              let thread = try await github.reviewThreads(repositoryPath: repositoryPath, number: number)
              .first(where: { $0.resolveID == threadID }),
              thread.isResolved == false, let latest = thread.comments.last?.id,
              try await github.pullRequestSummary(repositoryPath: repositoryPath, number: number)?.headCommit == head
        else {
            throw SessionServiceError("The pull request changed. Refresh before marking this conversation.")
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
