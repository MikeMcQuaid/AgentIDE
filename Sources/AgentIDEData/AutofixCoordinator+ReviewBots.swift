import AgentIDEDomain
import Foundation

extension AutofixCoordinator {
    func botReady(
        _ bot: ReviewBot,
        state: PullRequestAutomation,
        summary: PullRequestSummary,
        context: AutofixContext,
        fresh: Bool = false,
    ) async throws -> Bool {
        guard let head = summary.headCommit else {
            return false
        }

        let events = try await context.driver.reviewComments(state, fresh)
        let request = state.botRequest(bot)
        let completed = bot.completion(summary: summary, events: events)
        if request?.head == head {
            return completed != nil && bot.isWaiting(summary: summary, request: request, events: events) == false
        }
        let ready = completed != nil && bot.isWaiting(summary: summary, request: nil, events: events) == false
        guard try await context.driver.summary(state, true)?.headCommit == head else {
            return false
        }

        var claimed = false
        try context.store.updatePersisting { value in
            guard value.pullRequestAutomation[context.key]?.isAutomatic == true,
                  value.pullRequestAutomation[context.key]?.autofixBots == true,
                  value.pullRequestAutomation[context.key]?.reviewBot == state.reviewBot,
                  value.pullRequestAutomation[context.key]?.requestedBot(on: head).map({ $0 == bot }) != false,
                  value.pullRequestAutomation[context.key]?.botRequest(bot)?.head != head
            else {
                return
            }

            value.pullRequestAutomation[context.key]?.recordBotRequest(
                bot, head: head, date: ready ? nil : Date(), previousCompletion: completed?.id,
            )
            value.pullRequestAutomation[context.key]?.pending = ready ? ""
                : "Waiting for " + bot.displayName + "’s review"
            claimed = true
        }
        if claimed, ready == false, bot.isWaiting(summary: summary, request: nil, events: events) == false {
            try await context.driver.requestBot(state, bot)
        }
        return ready
    }
}
