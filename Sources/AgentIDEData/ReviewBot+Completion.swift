import AgentIDEDomain

public extension ReviewBot {
    internal func completion(summary: PullRequestSummary, events: [ReviewComment]) -> BotReviewCompletion? {
        switch self {
        case .copilot:
            events.filter { event in
                event.authorType == "Bot" && matches(event.author) && event.commit == summary.headCommit
                    && ["COMMENTED", "APPROVED", "CHANGES_REQUESTED"].contains(event.kind)
            }
            .compactMap { event in
                event.date.map { BotReviewCompletion(id: event.nodeID ?? String(event.id), date: $0) }
            }
            .max { $0.date < $1.date }

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
