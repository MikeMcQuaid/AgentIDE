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
