import AgentIDEDomain
import Foundation

// MARK: - BotReviewRequest

/// Evidence captured before requesting a remote review.
public struct BotReviewRequest: Codable, Equatable, Sendable {
    public let head: String?
    public let date: Date?
    public let previousCompletion: String?
}

public extension PullRequestAutomation {
    /// A missing preference keeps CodeRabbit disabled after an upgrade.
    var autofixCodeRabbit: Bool {
        get { codeRabbitEnabled == true }
        set { codeRabbitEnabled = newValue }
    }

    /// Existing bot opt-ins share one collection of automated feedback.
    var autofixBots: Bool {
        get { autofixCopilot || autofixCodeRabbit }
        set {
            let selected = reviewBot
            autofixCopilot = newValue
            codeRabbitEnabled = nil
            reviewBot = selected
        }
    }

    /// The provider to request, independent of the comments collected.
    var reviewBot: ReviewBot {
        get { preferredReviewBot ?? (autofixCodeRabbit ? .codeRabbit : .copilot) }
        set { preferredReviewBot = newValue }
    }

    /// A request already made on this head takes precedence over a later selection.
    func requestedBot(on head: String?) -> ReviewBot? {
        ReviewBot.allCases.first { bot in
            guard let request = botRequest(bot) else {
                return false
            }

            return request.date != nil && request.head == head
        }
    }

    internal func botRequest(_ bot: ReviewBot) -> BotReviewRequest? {
        botRequests?[bot] ?? (bot == .copilot && copilotHead != nil
            ? BotReviewRequest(head: copilotHead, date: copilotRequestedAt, previousCompletion: nil) : nil)
    }

    internal mutating func recordBotRequest(
        _ bot: ReviewBot,
        head: String?,
        date: Date?,
        previousCompletion: String? = nil,
    ) {
        botRequests = botRequests ?? [:]
        botRequests?[bot] = BotReviewRequest(head: head, date: date, previousCompletion: previousCompletion)
    }
}
