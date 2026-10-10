@testable import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [[], [.copilot], [.codeRabbit], [.copilot, .codeRabbit]] as [[ReviewBot]])
    func `only one bot in the conversation infers a reviewer`(bots: [ReviewBot]) {
        let model = makeModel()
        model.store.update { metadata in
            metadata.repositoryFeedbackDefaults["/repo"] = RepositoryFeedbackDefaults(reviewBot: .copilot)
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)] =
                CachedConversation(body: "", events: bots.enumerated().map { index, bot in
                    ReviewComment(id: index, author: bot.login + "[bot]", body: "Review", authorType: "Bot")
                })
        }
        #expect(model.selectedReviewBot(summary(7, head: "feature")) == (bots.count == 1 ? bots.first : nil))
        let stacked: ReviewBot? = model.selectedReviewBot(summary(8, head: "stacked"))
        #expect(stacked == nil)
    }

    @Test(arguments: ReviewBot.allCases)
    func `inline comments infer the reviewer including resolved threads`(bot: ReviewBot) {
        let model = makeModel()
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 7)] = CachedThreads(threads: [
                ReviewThread(id: "thread", path: "file", line: 1, isResolved: true, comments: [
                    ReviewThreadComment(author: bot.login, body: "Review", authorType: "Bot"),
                ]),
            ])
        }
        #expect(model.selectedReviewBot(summary(7, head: "feature")) == bot)
    }

    @Test
    func `unknown account types and other bots never choose a provider`() {
        let model = makeModel()
        model.store.update { metadata in
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)] =
                CachedConversation(body: "", events: [
                    ReviewComment(id: 1, author: ReviewBot.codeRabbit.login, body: "Unknown"),
                    ReviewComment(id: 2, author: ReviewBot.copilot.login, body: "Human", authorType: "User"),
                    ReviewComment(id: 3, author: "github-code-quality[bot]", body: "Quality", authorType: "Bot"),
                ])
        }
        let selected: ReviewBot? = model.selectedReviewBot(summary(7, head: "feature"))
        #expect(selected == nil)
    }
}
