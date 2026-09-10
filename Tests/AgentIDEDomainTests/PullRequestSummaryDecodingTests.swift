import AgentIDEDomain
import Foundation
import Testing

/// A summary an older release cached still decodes, its newer fields
/// at their defaults, so an upgrade never loses the metadata over it.
struct PullRequestSummaryDecodingTests {
    @Test
    func `a summary written before the newer fields decodes with defaults`() throws {
        let older = """
        {"number": 4, "title": "t", "url": "u", "headBranch": "h", "mergeable": "", "reviewDecision": "",
         "checks": "SUCCESS", "failingCheckLinks": [], "baseBranch": "main", "state": "OPEN",
         "isDraft": false, "hasAutomerge": false}
        """
        let summary = try JSONDecoder().decode(PullRequestSummary.self, from: Data(older.utf8))
        #expect(summary.number == 4)
        #expect(summary.checks == "SUCCESS")
        #expect(summary.unresolvedComments == 0)
        #expect(summary.isQueued == false)
        #expect(summary.awaitsCopilotReview == false)
        #expect(summary.copilotReviewedAt == nil)
    }
}
