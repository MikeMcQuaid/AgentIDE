import Foundation
@testable import SanductorData
import Testing

struct GitStashingTests {
    @Test(arguments: [false, true])
    func `temporary changes preserve existing stashes on success and failure`(fail: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("stash-preservation")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.makeRepository(at: root)
        try "older".write(toFile: root + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["stash", "push", "--message", "User's existing stash"], in: root)
        let existing = try await TestSupport.runGit(["stash", "list", "--format=%H"], in: root).standardOutput
        try "current".write(toFile: root + "/README.md", atomically: true, encoding: .utf8)
        let git = GitClient(runner: FoundationProcessRunner())
        do {
            try await git.preservingChanges(in: [root]) {
                #expect(await git.isDirty(worktreePath: root) == false)
                if fail {
                    throw SessionServiceError("Operation failed")
                }
            }
            #expect(fail == false)
        } catch {
            #expect(fail)
            #expect(error.localizedDescription == "Operation failed")
        }
        #expect(try String(contentsOfFile: root + "/README.md", encoding: .utf8) == "current")
        #expect(try await TestSupport.runGit(["stash", "list", "--format=%H"], in: root).standardOutput == existing)
    }

    @Test
    func `conflicting restoration keeps the stash recoverable`() async throws {
        let root = try TestSupport.temporaryDirectory("stash-conflict")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.makeRepository(at: root)
        try "local".write(toFile: root + "/README.md", atomically: true, encoding: .utf8)
        let git = GitClient(runner: FoundationProcessRunner())
        await #expect(throws: SessionServiceError.self) {
            try await git.preservingChanges(in: [root]) {
                try "upstream".write(toFile: root + "/README.md", atomically: true, encoding: .utf8)
                try await TestSupport.runGit(["add", "README.md"], in: root)
                try await TestSupport.runGit(["commit", "-m", "Upstream changes"], in: root)
            }
        }
        #expect(try await TestSupport.runGit(["show", "stash@{0}:README.md"], in: root).standardOutput == "local")
    }
}
