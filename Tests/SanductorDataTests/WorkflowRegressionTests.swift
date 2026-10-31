import Foundation
import SanductorData
import SanductorDomain
import Testing

struct WorkflowRegressionTests {
    @Test(arguments: ["renamed.md", "renamed space.md", "renamé.md", "quote\"tab\t.md"])
    func `untracked rename destinations remain one review file`(destination: String) async throws {
        let root = try TestSupport.temporaryDirectory("review-rename")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.makeRepository(at: root)
        try await TestSupport.runGit(["config", "diff.renames", "false"], in: root)
        try FileManager.default.moveItem(atPath: root + "/README.md", toPath: root + "/" + destination)
        let before = try await TestSupport.runGit(["status", "--porcelain"], in: root).standardOutput
        let diff = try await GitClient(runner: FoundationProcessRunner()).uncommittedDiff(worktreePath: root)
        let files = DiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files.first?.path == destination)
        #expect(files.first?.isNew == false)
        #expect(files.first?.oldPath == "README.md")
        #expect(try await TestSupport.runGit(["status", "--porcelain"], in: root).standardOutput == before)
        try await GitClient(runner: FoundationProcessRunner()).restoreFromHead(
            worktreePath: root, path: destination, oldPath: "README.md",
        )
        #expect(try await TestSupport.runGit(["status", "--porcelain"], in: root).standardOutput.isEmpty)
    }

    @Test
    func `cancelled jobs that never started have no log`() {
        let check = PullRequestCheck(
            name: "cancelled",
            status: "COMPLETED",
            conclusion: "CANCELLED",
            requirement: .optional,
            link: "https://github.com/o/r/actions/runs/1/job/2",
        )
        #expect(check.canReadLog == false)
    }
}
