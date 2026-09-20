import AgentIDEData
import Foundation
@testable import ReviewFeature
import Testing

extension ReviewModelTests {
    @Test
    func `last commit starts ticked and amends with at least one file kept`() async throws {
        let path = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("review-amend-" + UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        for file in ["one.txt", "two.txt"] {
            try "added\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        }
        let git = GitClient(runner: FoundationProcessRunner())
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Add both files"], in: path)
        let model = ReviewModel(worktreePath: path, repositoryName: "repo", git: git)
        model.scope = .lastCommit
        await model.reload()
        #expect(model.showsCommitTicks)
        #expect(model.committingCount == 2)
        #expect(model.canAmendLastCommit == false)

        model.setCommitting(false, path: "one.txt")
        #expect(model.canAmendLastCommit)
        model.setCommitting(false, path: "two.txt")
        model.commitMessage = "Keep two"
        #expect(model.canAmendLastCommit == false)
        let head = await git.commitHash(of: "HEAD", worktreePath: path)
        await model.amendLastCommit()
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == head)

        model.setCommitting(true, path: "two.txt")
        await model.amendLastCommit()
        #expect(model.files.map(\.path) == ["two.txt"])
        #expect(model.committingCount == 1)
        #expect(model.canAmendLastCommit == false)
        #expect(model.commitMessage == "Keep two")
        #expect(model.isAmending == false)
        #expect(await git.trackedFile(worktreePath: path, path: "one.txt") == nil)
        #expect(try String(contentsOfFile: path + "/one.txt", encoding: .utf8) == "added\n")

        model.commitMessage = "Rename the commit"
        #expect(model.canAmendLastCommit)
        await model.amendLastCommit()
        #expect(await git.trackedFile(worktreePath: path, path: "one.txt") == nil)
        #expect(try await git.commitMessage(worktreePath: path, commit: "HEAD") == "Rename the commit")
    }

    @Test
    func `scope changes and a new tip reset the ticks`() async throws {
        let path = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("review-ticks-" + UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let model = ReviewModel(
            worktreePath: path,
            repositoryName: "repo",
            git: GitClient(runner: FoundationProcessRunner()),
        )
        model.scope = .lastCommit
        await model.reload()
        model.setCommitting(false, path: "README.md")
        await model.reload()
        #expect(model.committingCount == 0)

        model.scope = .uncommitted
        #expect(model.excludedFromCommit.isEmpty)
        await model.reload()
        model.scope = .lastCommit
        await model.reload()
        #expect(model.committingCount == 1)
        model.setCommitting(false, path: "README.md")
        try "changed\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Change readme"], in: path)
        await model.reload()
        #expect(model.committingCount == 1)

        model.commitTarget = "HEAD^"
        #expect(model.showsCommitTicks == false)
        #expect(model.canAmendLastCommit == false)
        model.commitTarget = nil
        model.scope = .branch
        #expect(model.showsCommitTicks == false)
        #expect(model.canAmendLastCommit == false)
    }
}
