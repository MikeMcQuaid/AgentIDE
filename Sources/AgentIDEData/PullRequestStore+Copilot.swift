import AgentIDEDomain
import Foundation

public extension PullRequestStore {
    /// Manual and automatic requests share a durable claim before contacting GitHub.
    func claimBotReview(_ bot: ReviewBot, repositoryPath: String, summary: PullRequestSummary) throws {
        guard summary.state == "OPEN", summary.headCommit?.isEmpty == false else {
            throw SessionServiceError("Wait for the current PR head before requesting a review.")
        }

        let events = cachedConversation(repositoryPath: repositoryPath, number: summary.number).events
        var claimed = false
        try updateAutomation(repositoryPath: repositoryPath, summary: summary) { state in
            guard state.requestedBot(on: summary.headCommit).map({ $0 == bot }) != false,
                  bot.isWaiting(summary: summary, request: state.botRequest(bot), events: events) == false
            else {
                return
            }

            claimed = true
            state.reviewBot = bot
            state.recordBotRequest(
                bot,
                head: summary.headCommit,
                date: Date(),
                previousCompletion: bot.completion(summary: summary, events: events)?.id,
            )
        }
        guard claimed else {
            throw SessionServiceError("A review is already requested for this head.")
        }
    }

    /// The request shared by the header and automatic loop, including old Copilot stamps.
    func botReviewRequest(_ bot: ReviewBot, repositoryPath: String, summary: PullRequestSummary) -> BotReviewRequest? {
        let metadata = store.load()
        if let request = metadata.pullRequestAutomation[PullRequestAutomation.key(for: summary.url)]?.botRequest(bot) {
            return request
        }
        // Keep requests made by earlier releases pending across an upgrade.
        return bot == .copilot
            ? metadata.fetchedAt["copilot#" + Self.summaryKey(repositoryPath: repositoryPath, number: summary.number)]
            .map { BotReviewRequest(head: nil, date: $0, previousCompletion: nil) }
            : nil
    }
}
