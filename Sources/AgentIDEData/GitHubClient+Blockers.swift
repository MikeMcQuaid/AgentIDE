import Foundation

extension GitHubClient {
    func blockerState(repositoryPath: String, number: Int, isPullRequest: Bool) async throws -> String {
        try await gh(
            [isPullRequest ? "pr" : "issue", "view", String(number), "--json", "state", "--jq", ".state"],
            in: repositoryPath,
        )
        .standardOutput
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
