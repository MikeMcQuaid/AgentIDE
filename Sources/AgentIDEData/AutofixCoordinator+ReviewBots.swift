import AgentIDEDomain
import Foundation

extension AutofixCoordinator {
    func botReady(
        _ bot: ReviewBot, state: PullRequestAutomation, summary: PullRequestSummary, context: AutofixContext,
    ) async throws -> Bool {
        guard let head = summary.headCommit else {
            return false
        }

        let events = bot == .codeRabbit ? try await context.driver.reviewComments(state, false) : []
        let request = state.botRequest(bot)
        if request?.head == head {
            return bot.isWaiting(summary: summary, request: request, events: events) == false
        }
        let threads = try await context.driver.threads(state, false)
        let existing = threads.flatMap(\.comments).contains { comment in
            comment.authorType == "Bot" && bot.matches(comment.author)
                && comment.id.map { state.handledEvents.contains("comment:" + $0) == false } == true
        }
        let completed = bot.completion(summary: summary, events: events)
        let ready = (bot == .codeRabbit ? completed != nil : existing)
            && bot.isWaiting(summary: summary, request: nil, events: events) == false
        var claimed = false
        try context.store.updatePersisting { value in
            guard value.pullRequestAutomation[context.key]?.canStartRound == true,
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
