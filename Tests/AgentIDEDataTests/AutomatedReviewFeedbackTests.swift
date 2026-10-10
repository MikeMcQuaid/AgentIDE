@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct AutomatedReviewFeedbackTests {
    static let authors = [
        "copilot-pull-request-reviewer", "coderabbitai[bot]",
        "github-code-quality[bot]", "github-advanced-security",
    ]

    @Test(arguments: ReviewBot.allCases)
    func `either request choice collects all automated comments and excludes impersonators`(bot: ReviewBot) throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        let threads = Self.authors.flatMap { author in
            [
                AutofixFixture.thread(author, comment: author, author: author, type: "Bot"),
                AutofixFixture.thread("spoof", comment: "spoof", author: author, type: "User"),
                AutofixFixture.thread("unknown", comment: "unknown", author: author + "-other", type: "Bot"),
            ]
        }
        #expect(AutofixCandidate.reviews(threads: threads, head: "head", writers: [], state: state) == nil)
        state.autofixBots = true
        state.reviewBot = bot
        let candidate = try #require(AutofixCandidate.reviews(
            threads: threads, head: "head", writers: [], state: state,
        ))
        #expect(candidate.counts == [.copilot: 1, .codeRabbit: 1, .githubReview: 2])
        #expect(candidate.threads.keys.sorted() == Self.authors.sorted())
        #expect(candidate.text.contains("Fix spoof") == false)
        #expect(candidate.text.contains("Fix unknown") == false)
        state.handledEvents = candidate.events
        #expect(AutofixCandidate.reviews(threads: threads, head: "head", writers: [], state: state) == nil)
    }

    @Test
    func `copy candidates include both bots while the requested review is pending`() async throws {
        let fixture = try AutofixFixture()
        var state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        state.autofixBots = true
        state.reviewBot = .codeRabbit
        state.recordBotRequest(.codeRabbit, head: "head", date: Date())
        await fixture.update { value in
            value.comments = Self.authors.map { AutofixFixture.thread($0, comment: $0, author: $0, type: "Bot") }
        }
        let driver = await fixture.driver()
        let summary = try #require(await driver.summary(state, false))
        let candidate = try #require(await AutofixCoordinator().candidate(
            state: state, summary: summary, head: "head", fresh: true, driver: driver,
        ))
        #expect(candidate.counts.values.reduce(0, +) == 4)
        state.isAutomatic = true
        #expect(try await AutofixCoordinator().candidate(
            state: state, summary: summary, head: "head", fresh: true, driver: driver,
        ) == nil)
        #expect(await fixture.state.requestedBots.isEmpty)
    }

    @Test
    func `all automated threads use resolve on push and preserve follow-up comments`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            value.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true
            value.pullRequestAutomation[AutofixFixture.key]?.pushAutomatically = true
        }
        await fixture.update { value in
            value.comments = Self.authors.map { AutofixFixture.thread($0, comment: $0, author: $0, type: "Bot") }
            value.failPush = true
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        let attempt = try #require(await fixture.state.deliveries.first)
        #expect(attempt.threads.count == 4)
        await fixture.complete(addressed: Set(Self.authors.dropLast()))
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.resolutions.isEmpty)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions.count == 3)
        await fixture.update { value in
            value.comments[0] = AutofixFixture.thread(Self.authors[0], comment: "follow-up")
            value.head = "external-push"
            value.freshHead = "external-push"
        }
        let restarted = MetadataStore(file: fixture.directory + "/state.json")
        await AutofixCoordinator().refresh(store: restarted, driver: fixture.driver())
        await AutofixCoordinator().refresh(store: restarted, driver: fixture.driver())
        #expect(await fixture.state.resolutions.sorted() == Array(Self.authors[1 ... 2]).sorted())
        #expect(await fixture.state.deliveries.count == 1)
    }
}
