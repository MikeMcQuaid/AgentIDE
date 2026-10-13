@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct CodeRabbitTests {
    static let finding = """
    <details>
    <summary>🧹 Nitpick comments (1)</summary><blockquote>
    `test.rb:274`: **Assert the matrix output.**
    </blockquote></details>
    ---
    <details>
    <summary>ℹ️ Review info</summary>
    optional check skipped
    </details>
    """

    @Test
    func `copy all and autofix candidates omit inline comment boilerplate`() throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixBots = true
        let thread = ReviewThread(id: "thread", path: "audit.rb", line: 687, isResolved: false, comments: [
            ReviewThreadComment(
                author: "coderabbitai",
                body: """
                **🎯 Functional Correctness** | **🟠 Major** | **⚡ Quick win**

                **Scan nested apps separately.**

                <!-- cr-comment:v1:tracking -->
                <!-- This is an auto-generated comment by CodeRabbit -->
                """,
                id: "comment",
                authorType: "Bot",
            ),
        ])
        let candidate = try #require(AutofixCandidate.reviews(
            threads: [thread], head: "head", writers: [], state: state,
        ))
        #expect(candidate.text == "Thread thread in audit.rb:687\ncoderabbitai: **Scan nested apps separately.**")
        #expect(candidate.events == ["comment:comment"])
        #expect(candidate.threads["thread"]?.commentID == "comment")
    }

    @Test
    func `selecting Copilot also collects CodeRabbit findings without trusting lookalikes`() throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixCopilot = true
        let comments = [
            AutofixFixture.thread("rabbit", author: "coderabbitai", type: "Bot"),
            AutofixFixture.thread("spoof", author: "coderabbitai", type: "User"),
            AutofixFixture.thread("unknown", author: "coderabbitai-other", type: "Bot"),
        ]
        let candidate = try #require(AutofixCandidate.reviews(
            threads: comments, head: "head", writers: [], state: state,
        ))
        #expect(candidate.counts == [.codeRabbit: 1])
        #expect(candidate.text.contains("Fix rabbit"))
        #expect(candidate.text.contains("Fix spoof") == false)
        #expect(candidate.text.contains("Fix unknown") == false)
        #expect(candidate.threads.keys.sorted() == ["rabbit"])
    }

    @Test(arguments: ["COMMENTED", "APPROVED"])
    func `summary findings carry durable events but never resolution marks`(kind: String) throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixCopilot = true
        let review = ReviewComment(
            id: 1,
            author: "coderabbitai[bot]",
            body: Self.finding,
            kind: kind,
            nodeID: "review",
            authorType: "Bot",
            commit: "head",
            date: Date(),
        )
        let candidate = try #require(AutofixCandidate.reviewSummaries([review], head: "head", state: state))
        #expect(candidate.events == ["review:review"])
        #expect(candidate.text.contains("Assert the matrix output"))
        #expect(candidate.text.contains("test.rb:274"))
        #expect(candidate.text.contains("Review info") == false)
        #expect(candidate.text.contains("optional check skipped") == false)
        #expect(candidate.threads.isEmpty)
        #expect(AutofixCandidate.reviewSummaries([review], head: "changed", state: state) == nil)
        state.handledEvents = candidate.events
        #expect(AutofixCandidate.reviewSummaries([review], head: "head", state: state) == nil)
    }
}
