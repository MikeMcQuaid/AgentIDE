@testable import AgentIDEDomain
import Testing

/// What a pull request's summary says about itself.
struct PullRequestSummaryTests {
    @Test
    func `a push leaves the checks pending and nothing failing to go to`() {
        let failing = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://github.com/o/r/pull/7",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "FAILURE",
            failingCheckLinks: ["https://github.com/o/r/actions/runs/1"],
            baseBranch: "main",
            unresolvedComments: 2,
        )
        let pending = failing.awaitingChecks()
        #expect(pending.checks == "PENDING")
        #expect(pending.hasFailingChecks == false)
        #expect(pending.failingCheckLinks.isEmpty)
        // The rest is as it was: the push changed the commits, not
        // the review, the base or the conversation.
        #expect(pending.reviewDecision == "APPROVED")
        #expect(pending.unresolvedComments == 2)
        #expect(pending.number == 7)
    }
}
