@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct CodeRabbitCompletionTests {
    // MARK: Internal

    @Test
    func `an unrelated overview edit cannot answer a request but a new completed run can`() throws {
        let summary = PullRequestSummary(
            number: 1,
            title: "",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "head",
        )
        let before = overview(run: "first", head: "head", date: Date(timeIntervalSince1970: 10))
        let completed = try #require(CodeRabbitFeedback.completion([before], head: "head"))
        let request = BotReviewRequest(
            head: "head",
            date: Date(timeIntervalSince1970: 20),
            previousCompletion: completed.id,
        )
        let edited = overview(run: "first", head: "head", date: Date(timeIntervalSince1970: 30))
        #expect(ReviewBot.codeRabbit.isWaiting(summary: summary, request: request, events: [edited]))
        let submitted = ReviewComment(
            id: 2,
            author: "coderabbitai[bot]",
            body: "",
            kind: "APPROVED",
            nodeID: "new-review",
            authorType: "Bot",
            commit: "head",
            date: Date(timeIntervalSince1970: 25),
        )
        #expect(
            ReviewBot.codeRabbit.isWaiting(summary: summary, request: request, events: [edited, submitted]) == false,
        )
        let next = overview(run: "second", head: "head", date: Date(timeIntervalSince1970: 30))
        #expect(ReviewBot.codeRabbit.isWaiting(summary: summary, request: request, events: [next]) == false)
        #expect(CodeRabbitFeedback.completion([next], head: "changed") == nil)
        let spoof = ReviewComment(
            id: 1,
            author: "coderabbitai",
            body: next.body,
            nodeID: "spoof",
            authorType: "User",
            date: next.date,
        )
        #expect(CodeRabbitFeedback.completion([spoof], head: "head") == nil)
        #expect(CodeRabbitFeedback.findings(next, head: "head") == nil)
    }

    @Test
    func `paginated timeline rows retain identity permissions and review heads`() throws {
        let json = """
        [[{"id":1,"node_id":"review","user":{"login":"coderabbitai[bot]","type":"Bot"},
        "state":"COMMENTED","body":"Finding","commit_id":"head","submitted_at":"2026-10-06T21:31:27Z"}],
        [{"id":1,"node_id":"comment","user":{"login":"human","type":"User"},
        "body":"Reply","updated_at":"2026-10-06T21:32:00Z"}]]
        """
        let events = try GitHubClient.reviewComments(fromJSON: json)
        #expect(events.map(\.id) == [1, -1])
        #expect(events.map(\.nodeID) == ["review", "comment"])
        #expect(events.map(\.authorType) == ["Bot", "User"])
        #expect(events.first?.commit == "head")
        #expect(events.first?.date != nil)
        #expect(throws: (any Error).self) { try GitHubClient.reviewComments(fromJSON: "invalid") }
    }

    // MARK: Private

    private func overview(run: String, head: String, date: Date) -> ReviewComment {
        ReviewComment(
            id: 1,
            author: "coderabbitai[bot]",
            body: """
            <!-- recent_review_start -->
            No actionable comments were generated in the recent review. 🎉
            **Run ID**: `\(run)`
            Reviewing files that changed from the base of the PR and between previous and \(head).
            <!-- recent_review_end -->
            """,
            nodeID: "overview",
            authorType: "Bot",
            date: date,
        )
    }
}
