/// Actions runs, split from the client body for length.
public extension GitHubClient {
    /// The failed steps' log of one Actions run, as `gh` prints it.
    func failedRunLog(repositoryPath: String, runID: Int) async throws -> String {
        try await gh(["run", "view", String(runID), "--log-failed"], in: repositoryPath).standardOutput
    }
}
