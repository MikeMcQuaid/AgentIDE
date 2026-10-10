import AgentIDEData
import AgentIDEDomain
import TerminalUI

extension PullRequestsModel {
    func selectedReviewBot(_ summary: PullRequestSummary) -> ReviewBot? {
        _ = botAsks
        let state = store.load().pullRequestAutomation[PullRequestAutomation.key(for: summary.url)]
        if let requested = state?.requestedBot(on: summary.headCommit) {
            return requested
        }
        if ReviewBot.allCases.contains(where: { bot in
            pullRequests.botReviewRequest(bot, repositoryPath: repository.path, summary: summary)?.date != nil
        }) {
            return state?.reviewBot ?? .copilot
        }
        let conversation = pullRequests.cachedConversation(repositoryPath: repository.path, number: summary.number)
        let bots = ReviewBot.allCases.filter { bot in
            conversation.events.contains { $0.authorType == "Bot" && bot.matches($0.author) }
                || conversation.threads.contains { thread in
                    thread.comments.contains { $0.authorType == "Bot" && bot.matches($0.author) }
                }
        }
        return bots.count == 1 ? bots.first : nil
    }

    func canRequestBotReview(_ bot: ReviewBot, summary: PullRequestSummary) -> Bool {
        _ = botAsks
        guard summary.state == "OPEN", summary.headCommit?.isEmpty == false,
              ReviewBot.allCases.filter({ $0 != bot }).allSatisfy({ other in
                  guard let request = pullRequests.botReviewRequest(
                      other, repositoryPath: repository.path, summary: summary,
                  ) else {
                      return true
                  }

                  return request.date == nil || request.head != summary.headCommit
              })
        else {
            return false
        }

        return bot.isWaiting(
            summary: summary,
            request: pullRequests.botReviewRequest(bot, repositoryPath: repository.path, summary: summary),
            events: pullRequests.cachedConversation(repositoryPath: repository.path, number: summary.number).events,
        ) == false
    }

    func requestBotReview(_ bot: ReviewBot, summary: PullRequestSummary) async -> Bool {
        guard canRequestBotReview(bot, summary: summary) else {
            return false
        }

        let asked = await act {
            try pullRequests.claimBotReview(bot, repositoryPath: repository.path, summary: summary)
            botAsks += 1
            UtilityTabTarget.pullRequestCacheChanged()
            try await performBotRequest(bot, summary.number)
        }
        if asked {
            note("Asked " + bot.displayName + " to review #" + String(summary.number) + ".")
        }
        await refreshSummary(summary.number)
        return asked
    }
}
