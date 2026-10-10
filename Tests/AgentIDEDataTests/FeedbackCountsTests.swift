@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct FeedbackCountsTests {
    @Test
    func `counts describe copied items rather than CI runs or review rounds`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { value in
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixLocalReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            value.pullRequestAutomation[AutofixFixture.key]?.autofixCopilot = true
        }
        await fixture.update { value in
            value.localReview = LocalReview(reviewer: .claudeCode, snapshot: "diff", revision: "head", threads: [
                AutofixFixture.thread("local"),
            ])
            value.writers = ["human"]
            value.comments = [
                AutofixFixture.thread("human", comment: "human-comment"),
                AutofixFixture.thread("unverified", author: "outsider"),
                AutofixFixture.thread(
                    "copilot", comment: "bot-comment", author: "copilot-pull-request-reviewer", type: "Bot",
                ),
            ]
        }
        let state = try #require(fixture.store.load().pullRequestAutomation[AutofixFixture.key])
        let driver = await fixture.driver()
        let summary = try #require(await driver.summary(state, false))
        let candidate = try #require(await AutofixCoordinator().candidate(
            state: state, summary: summary, head: "head", fresh: false, driver: driver,
        ))
        #expect(candidate.counts == [.checks: 2, .localReview: 1, .reviews: 1, .copilot: 1])
        #expect(candidate.events.contains("run:2") == false)
        #expect(candidate.text.contains("outsider") == false)
    }

    @Test
    func `handled review comments are excluded from source counts`() throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: AutofixFixture.key)
        state.autofixReviews = true
        state.autofixCopilot = true
        state.handledEvents = ["comment:handled"]
        let thread = ReviewThread(id: "mixed", path: "file.swift", line: 1, isResolved: false, comments: [
            ReviewThreadComment(author: "human", body: "Old", id: "handled", authorType: "User"),
            ReviewThreadComment(author: "human", body: "New", id: "fresh", authorType: "User"),
            ReviewThreadComment(author: "unknown", body: "Ignored", id: "unknown", authorType: "User"),
        ])
        let candidate = try #require(AutofixCandidate.reviews(
            threads: [thread], head: "head", writers: ["human"], state: state,
        ))
        #expect(candidate.counts == [.reviews: 1])
        #expect(candidate.events == ["comment:fresh"])
    }
}
