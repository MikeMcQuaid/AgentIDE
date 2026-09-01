import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import ReviewFeature
import TerminalUI
import Testing

// MARK: - ReviewModelVanishedTests

/// A worktree can vanish between the poll that mounted its review
/// and the reload that reads it (a branch renamed away, cleanup
/// after a merge): that is the workspace changing, not a failure,
/// and it must not land in the messages pane as one.
struct ReviewModelVanishedTests {
    // MARK: Internal

    @Test
    func `a reload against a vanished worktree stays quiet`() async {
        let marker = "vanished-" + UUID().uuidString
        let model = makeModel(marker: marker)
        model.worktreeExists = { _ in false }

        await model.reload()
        #expect(model.hasLoaded)
        #expect(ErrorLog.shared.entries.contains { $0.message.contains(marker) } == false)
    }

    @Test
    func `a reload failing in a worktree still there reports`() async {
        let marker = "held-" + UUID().uuidString
        let model = makeModel(marker: marker)
        model.worktreeExists = { _ in true }

        await model.reload()
        #expect(ErrorLog.shared.entries.contains { $0.message.contains(marker) })
    }

    // MARK: Private

    private func makeModel(marker: String) -> ReviewModel {
        ReviewModel(
            worktreePath: "/worktrees/repo/renamed-away",
            repositoryName: "repo",
            git: GitClient(runner: FailingRunner(marker: marker)),
        )
    }
}

// MARK: - FailingRunner

/// Fails every command with a recognisable message, standing in for
/// git run inside a directory that no longer exists.
private struct FailingRunner: ProcessRunner {
    struct Failure: LocalizedError {
        let marker: String

        var errorDescription: String? {
            "The file \u{201C}" + marker + "\u{201D} doesn\u{2019}t exist."
        }
    }

    let marker: String

    func run(
        _: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) throws -> ProcessResult {
        throw Failure(marker: marker)
    }
}
