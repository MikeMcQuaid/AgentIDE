import AgentIDEDomain

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

    static func reviewSummaries(_ reviews: [ReviewComment], head: String, state: PullRequestAutomation) -> Self? {
        guard state.autofixBots else {
            return nil
        }

        return combine(reviews.compactMap { review in
            guard let id = review.nodeID, state.handledEvents.contains("review:" + id) == false,
                  let findings = CodeRabbitFeedback.findings(review, head: head)
            else {
                return nil
            }

            return Self(
                counts: [.codeRabbit: 1],
                sources: [.codeRabbit],
                events: ["review:" + id],
                text: "CodeRabbit review summary:\n" + findings,
                threads: [:],
            )
        })
    }
}
