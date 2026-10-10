import AgentIDEData
import AgentIDEDomain

extension DashboardModel {
    func feedbackStatus(for item: WorktreeItem) -> String? {
        _ = pullRequestCacheGeneration
        let states = store.load().pullRequestAutomation
        return ["local:" + item.worktree.path, pullRequest(for: item)?.url]
            .compactMap { $0.flatMap { states[PullRequestAutomation.key(for: $0)] } }
            .first { $0.repositoryPath == item.worktree.repositoryPath && $0.isLoopRunning }?
            .statusSummary
    }
}
