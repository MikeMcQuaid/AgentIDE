@testable import AgentIDEData
import Foundation
import Testing

/// A review request naming Copilot's bot is a review still waited
/// on, however gh spells the login.
extension GitHubClientTests {
    @Test
    func `a pending request of copilot is read from the listing`() {
        let waiting = """
        [{"number": 1, "title": "t", "url": "u", "headRefName": "h",
          "reviewRequests": [{"__typename": "Bot", "login": "copilot-pull-request-reviewer"}]}]
        """
        #expect(GitHubClient.summaries(fromJSON: waiting).first?.awaitsCopilotReview == true)
        let answered = """
        [{"number": 1, "title": "t", "url": "u", "headRefName": "h",
          "reviewRequests": [{"__typename": "User", "login": "mike"}]}]
        """
        #expect(GitHubClient.summaries(fromJSON: answered).first?.awaitsCopilotReview == false)
        // Copilot's latest review, dated, and nothing when a person's
        // is the only one.
        let reviewed = """
        [{"number": 1, "title": "t", "url": "u", "headRefName": "h",
          "latestReviews": [
            {"author": {"login": "mike"}, "submittedAt": "2026-09-10T10:00:00Z"},
            {"author": {"login": "copilot-pull-request-reviewer"}, "submittedAt": "2026-09-10T11:00:00Z"}]}]
        """
        let when = GitHubClient.summaries(fromJSON: reviewed).first?.copilotReviewedAt
        #expect(when.map { Calendar.current.component(.hour, from: $0) } != nil)
        #expect(GitHubClient.summaries(fromJSON: answered).first?.copilotReviewedAt == nil)
        // The poll's REST listing carries the same request, under
        // REST's own spelling of the bot.
        let rest = """
        [{"number": 1, "title": "t", "html_url": "u", "state": "open", "head": {"ref": "h"}, "base": {"ref": "main"},
          "requested_reviewers": [{"login": "copilot-pull-request-reviewer[bot]", "type": "Bot"}]}]
        """
        #expect(GitHubClient.summaries(fromRESTJSON: rest).first?.awaitsCopilotReview == true)
        #expect(GitHubClient.isCopilot("copilot-pull-request-reviewer[bot]"))
        #expect(GitHubClient.isCopilot("") == false)
        #expect(GitHubClient.isCopilot("copilot") == false)
        #expect(GitHubClient.isCopilot(nil) == false)
    }
}
