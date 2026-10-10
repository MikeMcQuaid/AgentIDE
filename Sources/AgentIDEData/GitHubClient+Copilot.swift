import AgentIDEDomain

public extension GitHubClient {
    /// GitHub’s reviewer request login.
    static let copilotReviewer = ReviewBot.copilot.login + "[bot]"

    /// CodeRabbit accepts a PR comment; Copilot uses GitHub's reviewer request API.
    func requestBotReview(_ bot: ReviewBot, repositoryPath: String, number: Int) async throws {
        let arguments =
            switch bot {
            case .copilot:
                [
                    "api", "--method", "POST", "repos/{owner}/{repo}/pulls/" + String(number) + "/requested_reviewers",
                    "-f", "reviewers[]=" + Self.copilotReviewer,
                ]

            case .codeRabbit:
                [
                    "api", "--method", "POST", "repos/{owner}/{repo}/issues/" + String(number) + "/comments",
                    "-f", "body=@coderabbitai review",
                ]
            }
        try await gh(arguments, in: repositoryPath)
    }

    /// Exact REST or GraphQL login, never a similar human account.
    static func isCopilot(_ login: String?) -> Bool {
        ReviewBot.copilot.matches(login)
    }
}
