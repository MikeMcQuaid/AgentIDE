@testable import AgentIDEData
import Foundation
import Testing

// MARK: - OfflineGateTests

/// One offline check in front of every network call. A machine with
/// no route cannot succeed at any of them, so each is refused before
/// a process is spawned rather than after it has failed: that is
/// what kept the messages pane full and `gh` running per branch per
/// poll.
struct OfflineGateTests {
    @Test
    func `github calls are refused before anything is spawned`() async {
        let runner = RecordingRunner()
        let github = GitHubClient(runner: runner) { false }

        _ = await github.labels(repositoryPath: "/repo")
        #expect(runner.commands.isEmpty)

        // The refusal itself reaches anything that throws.
        await #expect(throws: Error.self) {
            try await github.merge(repositoryPath: "/repo", number: 1)
        }
    }

    @Test
    func `a network git command is refused and a local one is not`() async throws {
        let runner = RecordingRunner()
        let git = GitClient(runner: runner) { false }

        await #expect(throws: Error.self) {
            try await git.fetch(repositoryPath: "/repo")
        }
        #expect(runner.commands.isEmpty)

        // Reading the worktree needs no network, and a stale answer
        // beats no answer while the route is gone.
        _ = await git.currentBranch(worktreePath: "/repo")
        #expect(runner.commands.isEmpty == false)
    }

    @Test
    func `the refusal reads as an outage, so it is pooled not repeated`() {
        let refusal = OfflineError(doing: "Fetching brew")
        #expect(GitHubOutage.isLikely(refusal))
        #expect(refusal.localizedDescription.contains("Fetching brew"))
    }

    @Test
    func `an online client is not gated at all`() async {
        let runner = RecordingRunner()
        let github = GitHubClient(runner: runner) { true }
        _ = await github.labels(repositoryPath: "/repo")
        #expect(runner.commands.isEmpty == false)
    }
}
