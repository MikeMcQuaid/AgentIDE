import AgentIDEDomain
import AppKit
@testable import PRFeature
import SwiftUI
import TerminalUI
import Testing

@MainActor
struct PullRequestTimelineTests {
    @Test
    func `timeline keeps the last entry per bot and every human comment`() {
        let events = [
            ReviewComment(id: 1, author: "coderabbitai", body: "Old review", kind: "COMMENTED"),
            ReviewComment(id: 2, author: "reviewer", body: "First reply"),
            ReviewComment(id: 3, author: "copilot-pull-request-reviewer", body: "Old review"),
            ReviewComment(id: 4, author: "coderabbitai[bot]", body: "Current overview"),
            ReviewComment(id: 5, author: "reviewer", body: "Second reply"),
            ReviewComment(id: 6, author: "copilot-pull-request-reviewer[bot]", body: "Current review"),
        ]
        let timeline = PullRequestTimeline(description: "", events: events)
        #expect(timeline.events.map(\.id) == [2, 4, 5, 6])
        #expect(timeline.events == events.filter { [2, 4, 5, 6].contains($0.id) })
    }

    @Test
    func `timeline entries keep compact headers above full width comments`() async throws {
        let host = NSHostingView(rootView: PullRequestTimeline(description: "", events: [
            ReviewComment(id: 1, author: "reviewer", body: "Comment."),
            ReviewComment(id: 2, author: "reviewer", body: "Comment."),
        ]).frame(width: 400))
        let author = NSHostingView(rootView: Text("reviewer").interfaceFont(.callout, weight: .bold))
        let comment = NSHostingView(rootView: MarkdownText("Comment.").frame(width: 390))
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            author.layoutSubtreeIfNeeded()
            comment.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let rowHeight = author.fittingSize.height + 4 + comment.fittingSize.height
        #expect(abs(host.fittingSize.height - (2 * rowHeight + 10)) < 1)
    }

    @Test(arguments: ReviewBot.allCases)
    func `latest bot entry follows dates across reviews and issue comments`(_ bot: ReviewBot) {
        let current = ReviewComment(
            id: 1, author: bot.login, body: "Latest review", date: Date(timeIntervalSince1970: 2),
        )
        let older = ReviewComment(
            id: 2, author: bot.login + "[bot]", body: "Older overview", date: Date(timeIntervalSince1970: 1),
        )
        #expect(PullRequestTimeline(description: "", events: [current, older]).events == [current])
    }

    @Test(arguments: ReviewBot.allCases)
    func `bot totals appear only when earlier entries are hidden`(_ bot: ReviewBot) {
        let older = ReviewComment(id: 1, author: bot.login, body: "Older review")
        let latest = ReviewComment(id: 2, author: bot.login + "[bot]", body: "Latest review")
        let human = ReviewComment(id: 3, author: "reviewer", body: "Reply")
        let timeline = PullRequestTimeline(description: "", events: [older, human, latest])
        #expect(timeline.headerDetail(for: latest) == "Latest of 2 comments")
        #expect(timeline.headerDetail(for: human).isEmpty)
        #expect(PullRequestTimeline(description: "", events: [latest]).headerDetail(for: latest).isEmpty)
    }
}
