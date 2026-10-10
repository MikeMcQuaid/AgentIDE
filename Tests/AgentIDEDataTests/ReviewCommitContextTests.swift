@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct ReviewCommitContextTests {
    @Test
    func `large committed changes include full messages and exclude later working edits`() async throws {
        let path = try TestSupport.temporaryDirectory("review-commits")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let base = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        let content = String(repeating: "large change\n", count: 30_000)
        try content.write(toFile: path + "/large.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "large.txt"], in: path)
        try await TestSupport.runGit(["commit", "-m", "Add data\n\nExplain why this data is needed."], in: path)
        let head = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "uncommitted evidence".write(toFile: path + "/large.txt", atomically: true, encoding: .utf8)
        let context = try await git.reviewCommitContext(worktreePath: path, revisions: [head])
        #expect(context.contains(head))
        #expect(context.contains("Add data\n\nExplain why this data is needed."))
        #expect(context.contains("Initial commit") == false)
        #expect(try await git.reviewCommitContext(worktreePath: path, revisions: [base + ".." + head]) == context)
        #expect(try await git.reviewCommitContext(worktreePath: path, revisions: []).isEmpty)
        let snapshot = try await LocalReviewInput.snapshot(files: DiffParser.parse(git.commitDiff(
            worktreePath: path, commit: head,
        )))
        #expect(snapshot.utf8.count > LocalReviewInput.byteLimit)
        let prompt = try LocalReviewInput.prompt(
            instructions: "Review these changes.", snapshot: snapshot, commitContext: context,
        )
        #expect(prompt.contains("Explain why this data is needed."))
        #expect(prompt.contains("uncommitted evidence") == false)
        #expect(prompt.hasSuffix(snapshot))
    }
}
