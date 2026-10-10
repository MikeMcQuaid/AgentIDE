import AgentIDEDomain
import Foundation
@testable import PRFeature
import Synchronization
import Testing

/// Asking Copilot for a review, once per push.
extension PullRequestsModelTests {
    @Test
    func `copilot is asked for a review, and not again while one waits`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        let asked = Mutex([Int]())
        model.performBotRequest = { _, number in asked.withLock { $0.append(number) } }
        let open = reviewed(7)
        #expect(model.canRequestBotReview(.copilot, summary: open))
        #expect(await model.requestBotReview(.copilot, summary: open))
        #expect(asked.withLock { $0 } == [7])

        // A request still waiting on Copilot dims the button; a
        // merged pull request has nothing left to review.
        let waiting = PullRequestSummary(
            number: 7,
            title: "Title",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "head",
            awaitsCopilotReview: true,
        )
        #expect(model.canRequestBotReview(.copilot, summary: waiting) == false)
        #expect(model.canRequestBotReview(.copilot, summary: summary(7, head: "feature", state: "MERGED")) == false)

        // The ask itself is remembered, in the metadata, until a
        // review newer than it is seen: GitHub's own request comes
        // and goes as Copilot starts, and the poll's listing carries
        // no reviews at all.
        #expect(model.canRequestBotReview(.copilot, summary: open) == false)
        let reviewedBefore = reviewed(7, at: Date().addingTimeInterval(-60))
        #expect(model.canRequestBotReview(.copilot, summary: reviewedBefore) == false)
        let reviewedAfter = reviewed(7, at: Date().addingTimeInterval(60))
        #expect(model.canRequestBotReview(.copilot, summary: reviewedAfter))
    }

    @Test
    func `a CodeRabbit request prevents requesting Copilot on the same head`() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path
        defer {
            try? FileManager.default.removeItem(atPath: file)
            try? FileManager.default.removeItem(atPath: file + ".restart")
        }
        let model = makeModel(items: [item(branch: "feature", ahead: 0)], metadataFile: file)
        let asked = Mutex([ReviewBot]())
        model.performBotRequest = { bot, _ in asked.withLock { $0.append(bot) } }
        let open = reviewed(7)
        #expect(await model.requestBotReview(.codeRabbit, summary: open))
        #expect(await model.requestBotReview(.codeRabbit, summary: open) == false)
        #expect(model.canRequestBotReview(.copilot, summary: open) == false)
        #expect(asked.withLock { $0 } == [.codeRabbit])
        #expect(model.selectedReviewBot(open) == .codeRabbit)
        try FileManager.default.copyItem(atPath: file, toPath: file + ".restart")
        let restarted = makeModel(metadataFile: file + ".restart")
        #expect(restarted.selectedReviewBot(open) == .codeRabbit)
        restarted.store.update { $0.pullRequestAutomation[open.url]?.reviewBot = .copilot }
        #expect(restarted.selectedReviewBot(open) == .codeRabbit)
        #expect(model.store.load().pullRequestAutomation.values.allSatisfy { $0.isAutomatic == false })
    }

    @Test
    func `a missing head cannot bypass the single reviewer request guard`() {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        let unknown = summary(7, head: "feature")
        #expect(model.canRequestBotReview(.copilot, summary: unknown) == false)
        #expect(model.canRequestBotReview(.codeRabbit, summary: unknown) == false)
    }

    private func reviewed(_ number: Int, at date: Date? = nil) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "head",
            copilotReviewedAt: date,
        )
    }
}
