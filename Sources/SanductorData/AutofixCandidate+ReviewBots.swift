import Foundation
import SanductorDomain

extension AutofixCandidate {
    static func botSource(author: String, type: String?) -> AutofixAttempt.Kind? {
        guard type == "Bot" else {
            return nil
        }

        if ReviewBot.copilot.matches(author) {
            return .copilot
        }
        if ReviewBot.codeRabbit.matches(author) {
            return .codeRabbit
        }
        if [
            "github-code-quality", "github-code-quality[bot]",
            "github-advanced-security", "github-advanced-security[bot]",
        ].contains(author) {
            return .githubReview
        }
        return nil
    }

    static func reviewSummaries(
        _ reviews: [ReviewComment], head: String, state: PullRequestAutomation, writers: Set<String> = [],
    ) -> Self? {
        guard state.autofixBots || state.autofixReviews else {
            return nil
        }

        return combine(reviews.compactMap { review in
            guard let id = review.nodeID, state.handledEvents.contains("review:" + id) == false else {
                return nil
            }

            let human = state.autofixReviews && review.authorType == "User" && writers.contains(review.author)
                && review.commit == head && ["COMMENTED", "CHANGES_REQUESTED"].contains(review.kind)
            let findings = human ? review.body
                : state.autofixBots ? CodeRabbitFeedback.findings(review, head: head) : nil
            guard let findings, findings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }

            let kind: AutofixAttempt.Kind = human ? .reviews : .codeRabbit
            return Self(
                counts: [kind: 1],
                sources: [kind],
                events: ["review:" + id],
                text: review.author + " review summary:\n" + findings,
                threads: [:],
            )
        })
    }
}
