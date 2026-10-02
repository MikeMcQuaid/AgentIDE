import AgentIDEData
import AgentIDEDomain

/// What the model's GitHub and service seams do when they are the
/// real ones, split from the initialiser for length.
extension PullRequestsModel {
    /// The one merge action: takes a draft out of draft, cancels
    /// automerge, merges what is ready, or asks for automerge.
    static func mergeChange(
        _ summary: PullRequestSummary,
        github: GitHubClient,
        repository: Repository,
        gate: PullRequestStore,
    ) async throws -> GitHubClient.MergeResult? {
        defer { gate.invalidate(repositoryPath: repository.path, number: summary.number) }
        if summary.isDraft {
            try await github.markReady(repositoryPath: repository.path, number: summary.number)
        } else if summary.hasAutomerge {
            try await github.disableAutomerge(repositoryPath: repository.path, number: summary.number)
        } else if isReadyToMerge(summary) {
            return try await github.merge(repositoryPath: repository.path, number: summary.number)
        } else {
            try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number)
        }
        return nil
    }

    /// Whether the default branch takes a push, a no when there is
    /// no default branch to ask about.
    static func acceptsDefaultPushes(gate: PullRequestStore, repository: Repository, defaultBranch: String?) async
        -> Bool
    {
        guard let defaultBranch else {
            return false
        }

        return await gate.acceptsDefaultPushes(repositoryPath: repository.path, branch: defaultBranch)
    }

    /// A pull request's conversations. One that fell back to REST is
    /// a recovery that worked, so it goes only to the messages log.
    static func threads(of number: Int, gate: PullRequestStore, repository: Repository) async -> [ReviewThread] {
        let answer = try? await gate.conversation(repositoryPath: repository.path, number: number, seededBody: nil)
        if let failure = answer?.graphQLFailure {
            PerformanceLog.recordMessage(
                "Conversations fell back to REST (no resolve buttons): " + failure,
                isError: false,
            )
        }
        return answer?.threads ?? []
    }
}
