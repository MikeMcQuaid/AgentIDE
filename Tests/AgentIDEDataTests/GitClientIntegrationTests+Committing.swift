@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Committing named paths and leaving the rest alone; split from
/// the client's integration tests for length.
extension GitClientIntegrationTests {
    @Test
    func `a commit of named files leaves everything else uncommitted`() async throws {
        let root = try TestSupport.temporaryDirectory("git-partial")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let git = GitClient(runner: FoundationProcessRunner())
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)

        // One file the agent changed, one it added, and one to be
        // left behind; a new file matters because a commit given a
        // pathspec refuses a path git has never seen.
        try "edited\n".write(toFile: repoPath + "/README.md", atomically: true, encoding: .utf8)
        try "added\n".write(toFile: repoPath + "/added.txt", atomically: true, encoding: .utf8)
        try "later\n".write(toFile: repoPath + "/later.txt", atomically: true, encoding: .utf8)

        try await git.commit(
            worktreePath: repoPath,
            paths: ["README.md", "added.txt"],
            message: "Take two of the three",
        )

        #expect(try await git.lastCommitMessage(worktreePath: repoPath) == "Take two of the three")
        let committed = try await git.lastCommitDiff(worktreePath: repoPath)
        #expect(committed.contains("+edited"))
        #expect(committed.contains("+added"))
        #expect(committed.contains("+later") == false)
        // The file nobody ticked is still there to commit.
        #expect(await git.isDirty(worktreePath: repoPath))

        // And committing nothing is not a commit at all.
        let before = try await git.lastCommitMessage(worktreePath: repoPath)
        try await git.commit(worktreePath: repoPath, paths: [], message: "Nothing to see")
        #expect(try await git.lastCommitMessage(worktreePath: repoPath) == before)
    }

    @Test
    func `an amend folds named files into the last commit and leaves the rest`() async throws {
        let root = try TestSupport.temporaryDirectory("git-amend")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let git = GitClient(runner: FoundationProcessRunner())
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)

        try "first\n".write(toFile: repoPath + "/first.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: repoPath, message: "The commit being added to")
        let before = try await git.commitCount(worktreePath: repoPath, range: "HEAD")

        // One file to fold in, one to leave behind.
        try "edited\n".write(toFile: repoPath + "/README.md", atomically: true, encoding: .utf8)
        try "later\n".write(toFile: repoPath + "/later.txt", atomically: true, encoding: .utf8)
        try await git.amend(worktreePath: repoPath, paths: ["README.md"], message: nil)

        // One commit, not two, and its message is the one it had.
        #expect(try await git.commitCount(worktreePath: repoPath, range: "HEAD") == before)
        #expect(try await git.lastCommitMessage(worktreePath: repoPath) == "The commit being added to")
        let amended = try await git.lastCommitDiff(worktreePath: repoPath)
        #expect(amended.contains("+edited"))
        #expect(amended.contains("+first"))
        #expect(amended.contains("+later") == false)
        // What was not ticked is still waiting to be committed.
        #expect(await git.isDirty(worktreePath: repoPath))
    }
}
