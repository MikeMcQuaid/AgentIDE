extension GitHubClient {
    /// Reads local credential availability without exposing a token or contacting GitHub.
    func hasStoredAuthentication() async -> Bool {
        let result = try? await runner.run(
            ["/bin/zsh", "-fc", "gh auth token --hostname github.com &>/dev/null"],
            workingDirectory: nil,
            environment: [:],
        )
        return result?.succeeded == true
    }
}
