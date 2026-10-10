@testable import AgentIDEData
import AgentIDEDomain
import Testing

// MARK: - ReviewBotRequestTests

struct ReviewBotRequestTests {
    @Test
    func `an empty submitted review still confirms bot completion`() throws {
        let events = try GitHubClient.reviewComments(fromJSON: """
        [[{"id":1,"node_id":"review","user":{"login":"coderabbitai[bot]","type":"Bot"},
        "state":"COMMENTED","body":"","commit_id":"head","submitted_at":"2026-10-06T21:31:27Z"}]]
        """)
        #expect(CodeRabbitFeedback.completion(events, head: "head") != nil)
    }

    @Test(arguments: ReviewBot.allCases)
    func `a manual claim allows either provider only after the next pushed head`(next: ReviewBot) async throws {
        let fixture = try AutofixFixture()
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        let driver = await fixture.driver()
        let summary = try #require(await driver.summary(state, false))
        let github = GitHubClient(runner: BotRequestRunner()) { true }
        let gate = PullRequestStore(github: github, store: fixture.store)
        try gate.claimBotReview(.codeRabbit, repositoryPath: "/repo", summary: summary)
        #expect(throws: (any Error).self) {
            try gate.claimBotReview(.copilot, repositoryPath: "/repo", summary: summary)
        }
        await fixture.update { $0.head = "pushed" }
        let pushed = try #require(await driver.summary(state, false))
        try gate.claimBotReview(next, repositoryPath: "/repo", summary: pushed)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.requestedBot(on: "pushed") == next)
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.autofixBots == false)
    }

    @Test(arguments: ReviewBot.allCases)
    func `requests name the selected PR and use the provider protocol`(bot: ReviewBot) async throws {
        let runner = BotRequestRunner()
        let github = GitHubClient(runner: runner) { true }
        try await github.requestBotReview(bot, repositoryPath: "/base-repository", number: 42)
        let request = try #require(await runner.requests.first)
        #expect(request.directory == "/base-repository")
        if bot == .codeRabbit {
            #expect(request.arguments.contains("repos/{owner}/{repo}/issues/42/comments"))
            #expect(request.arguments.contains("body=@coderabbitai review"))
        } else {
            #expect(request.arguments.contains("repos/{owner}/{repo}/pulls/42/requested_reviewers"))
            #expect(request.arguments.contains("reviewers[]=copilot-pull-request-reviewer[bot]"))
        }
    }
}

// MARK: - BotRequestRunner

private actor BotRequestRunner: ProcessRunner {
    struct Request {
        let arguments: [String]
        let directory: String?
    }

    var requests: [Request] = []

    func run(
        _ arguments: [String], workingDirectory: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        requests.append(Request(arguments: arguments, directory: workingDirectory))
        return ProcessResult(status: 0, standardOutput: "", standardError: "")
    }
}
