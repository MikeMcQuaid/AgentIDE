import AgentIDEData
import AgentIDEDomain
import TerminalUI

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
    ) async throws {
        defer { gate.invalidate(repositoryPath: repository.path, number: summary.number) }
        if summary.isDraft {
            try await github.markReady(repositoryPath: repository.path, number: summary.number)
        } else if summary.hasAutomerge {
            try await github.disableAutomerge(repositoryPath: repository.path, number: summary.number)
        } else if isReadyToMerge(summary) {
            try await github.merge(repositoryPath: repository.path, number: summary.number)
        } else {
            try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number)
        }
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

    /// Tidies up after a merge and says what it did and could not.
    static func cleanUpAfterMerge(worktree: Worktree, mergedBranch: String, service: SessionService) async {
        let report = await service.cleanUpAfterMerge(worktree: worktree, mergedBranch: mergedBranch)
        for note in report.notes {
            ErrorLog.shared.note(note)
        }
        for failure in report.failures {
            ErrorLog.shared.report(failure)
        }
        // The cleanup changed the checked-out branch and deleted
        // others, so the sidebar's rows are stale the moment it
        // finishes; waiting for the next poll showed a branch that
        // no longer exists.
        Self.requestSidebarRefresh()
    }
}
