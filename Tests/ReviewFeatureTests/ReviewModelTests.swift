import AgentIDEData
import Foundation
@testable import ReviewFeature
import Testing

/// Exercises the review model's scopes against a real repository, so
/// each scope button reliably changes what the pane shows.
struct ReviewModelTests {
    // MARK: Internal

    @Test
    func `scopes show their own diffs even with uncommitted changes present`() async throws {
        let path = "/tmp/agentide-review-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        try "committed\n".write(toFile: path + "/committed.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Add committed file"], in: path)
        try "dirty\n".write(toFile: path + "/dirty.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)

        let model = ReviewModel(worktreePath: path, git: GitClient(runner: FoundationProcessRunner()))
        model.scope = .lastCommit
        await model.reload()
        #expect(model.files.map(\.path) == ["committed.txt"])
        #expect(model.showsUncommitted == false)

        model.scope = .uncommitted
        await model.reload()
        #expect(model.files.map(\.path) == ["dirty.txt"])
        #expect(model.showsUncommitted)
    }

    // MARK: Private

    private func makeRepository(at path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "main"], in: path)
        try await runGit(["config", "user.email", "test@example.com"], in: path)
        try await runGit(["config", "user.name", "Test"], in: path)
        try "hello\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Initial commit"], in: path)
    }

    private func runGit(_ arguments: [String], in directory: String) async throws {
        _ = try await FoundationProcessRunner().run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"] + arguments,
            workingDirectory: directory,
            environment: [:],
        )
    }
}
