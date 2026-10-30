extension GitHubClient {
    /// Checks credential availability without exposing a token; gh refreshes it when needed.
    func hasStoredAuthentication() async -> Bool {
        let result = try? await runner.run(
            ["/bin/zsh", "-fc", "gh auth token --hostname github.com &>/dev/null"],
            workingDirectory: nil,
            environment: [:],
        )
        return result?.succeeded == true
    }
}
