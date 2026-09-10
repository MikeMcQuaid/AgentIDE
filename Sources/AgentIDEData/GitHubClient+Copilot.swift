/// Asking Copilot for a review. Split from the client body for
/// length.
public extension GitHubClient {
    /// The reviewer Copilot is, as a review request names it.
    static let copilotReviewer = "copilot-pull-request-reviewer[bot]"

    /// Asks Copilot to review a pull request, or to review it again
    /// after a push: a review request naming its bot, which is what
    /// the button beside its name in the Reviewers list sends too.
    func requestCopilotReview(repositoryPath: String, number: Int) async throws {
        try await gh(
            [
                "api", "--method", "POST", "repos/{owner}/{repo}/pulls/" + String(number) + "/requested_reviewers",
                "-f", "reviewers[]=" + Self.copilotReviewer,
            ],
            in: repositoryPath,
        )
    }

    /// Whether a login is Copilot's: the reviewer's, with or without
    /// the bot suffix gh's GraphQL fields drop, and nothing else.
    static func isCopilot(_ login: String?) -> Bool {
        login == copilotReviewer || login == copilotReviewer.replacing("[bot]", with: "")
    }
}
