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
        model.performCopilotRequest = { number in asked.withLock { $0.append(number) } }
        let open = summary(7, head: "feature")
        #expect(model.canRequestCopilotReview(open))
        #expect(await model.requestCopilotReview(open))
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
            awaitsCopilotReview: true,
        )
        #expect(model.canRequestCopilotReview(waiting) == false)
        #expect(model.canRequestCopilotReview(summary(7, head: "feature", state: "MERGED")) == false)

        // The ask itself is remembered, in the metadata, until a
        // review newer than it is seen: GitHub's own request comes
        // and goes as Copilot starts, and the poll's listing carries
        // no reviews at all.
        #expect(model.canRequestCopilotReview(open) == false)
        let reviewedBefore = reviewed(7, at: Date().addingTimeInterval(-60))
        #expect(model.canRequestCopilotReview(reviewedBefore) == false)
        let reviewedAfter = reviewed(7, at: Date().addingTimeInterval(60))
        #expect(model.canRequestCopilotReview(reviewedAfter))
    }

    private func reviewed(_ number: Int, at date: Date) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            copilotReviewedAt: date,
        )
    }
}
