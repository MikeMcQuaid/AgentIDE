import AgentIDEDomain

public extension ReviewBot {
    internal func completion(summary: PullRequestSummary, events: [ReviewComment]) -> BotReviewCompletion? {
        switch self {
        case .copilot:
            summary.copilotReviewedAt.map { BotReviewCompletion(id: $0.description, date: $0) }

        case .codeRabbit:
            summary.headCommit.flatMap { CodeRabbitFeedback.completion(events, head: $0) }
        }
    }

    /// Only a new completed review answers a durable request.
    func isWaiting(summary: PullRequestSummary, request: BotReviewRequest?, events: [ReviewComment]) -> Bool {
        if self == .copilot, summary.awaitsCopilotReview {
            return true
        }
        guard let request, let asked = request.date else {
            return false
        }

        if let requestedHead = request.head, let currentHead = summary.headCommit, requestedHead != currentHead {
            return false
        }

        let completed = self == .codeRabbit
            ? CodeRabbitFeedback.completions(events, head: summary.headCommit ?? "")
            : completion(summary: summary, events: events).map { [$0] } ?? []
        return completed.contains { $0.date > asked && $0.id != request.previousCompletion } == false
    }
}
