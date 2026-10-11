import AgentIDEData
import Foundation
@testable import ReviewFeature
import Testing

extension ReviewModelTests {
    @Test
    func `local reviews follow the selected commit branch and uncommitted scopes`() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let base = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try await runGit(["checkout", "-b", "topic"], in: path)
        try "change\n".write(toFile: path + "/file.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "--", "file.txt"], in: path)
        try await runGit(["commit", "-m", "First change\n\nFirst reason."], in: path)
        let first = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try await runGit(["commit", "--allow-empty", "-m", "Second change\n\nSecond reason."], in: path)
        let model = ReviewModel(worktreePath: path, repositoryName: "repo", git: git) { base }
        model.scope = .lastCommit
        await model.reload()
        #expect(model.files.isEmpty)
        #expect(model.localReviewContext.contains("Second reason."))
        #expect(model.localReviewContext.contains("First reason.") == false)

        model.commitTarget = first
        await model.reload()
        #expect(model.localReviewContext.contains(first))
        #expect(model.localReviewContext.contains("First reason."))
        #expect(model.localReviewContext.contains("Second reason.") == false)

        model.commitTarget = nil
        model.scope = .branch
        await model.reload()
        #expect(model.localReviewContext.contains("First reason."))
        #expect(model.localReviewContext.contains("Second reason."))
        #expect(model.localReviewContext.contains("Initial commit") == false)

        model.stackTarget = (parent: first, branch: "topic")
        await model.reload()
        #expect(model.localReviewContext.contains("First reason.") == false)
        #expect(model.localReviewContext.contains("Second reason."))

        model.stackTarget = nil
        model.scope = .uncommitted
        await model.reload()
        #expect(model.localReviewContext.isEmpty)
    }
}
