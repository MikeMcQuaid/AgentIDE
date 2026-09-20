@testable import AgentIDEData
import Foundation
import Testing

extension GitClientIntegrationTests {
    @Test
    func `a refused amend leaves the commit and staged work intact`() async throws {
        let path = try TestSupport.temporaryDirectory("uncommit-refused")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        try "changed\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try "added\n".write(toFile: path + "/added.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: path, message: "Two files")
        let head = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "staged\n".write(toFile: path + "/added.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "added.txt"], in: path)
        let index = try await TestSupport.runGit(["write-tree"], in: path).standardOutput
        try await TestSupport.runGit(["config", "commit.gpgsign", "true"], in: path)
        try await TestSupport.runGit(["config", "gpg.format", "openpgp"], in: path)
        try await TestSupport.runGit(["config", "gpg.program", "/usr/bin/false"], in: path)

        await #expect(throws: (any Error).self) {
            try await git.amend(worktreePath: path, excluding: ["README.md"], message: "Kept", expectedHead: head)
        }
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == head)
        #expect(try await TestSupport.runGit(["write-tree"], in: path).standardOutput == index)
        #expect(try String(contentsOfFile: path + "/added.txt", encoding: .utf8) == "staged\n")
    }

    @Test
    func `unticked files leave the commit without changing the index or working tree`() async throws {
        let path = try TestSupport.temporaryDirectory("uncommit")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        try "old\n".write(toFile: path + "/removed.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: path, message: "Base")
        let parent = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "changed\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try "added\n".write(toFile: path + "/added.txt", atomically: true, encoding: .utf8)
        try "kept\n".write(toFile: path + "/kept.txt", atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: path + "/removed.txt")
        try await git.commitAll(worktreePath: path, message: "All changes")
        let head = try #require(await git.commitHash(of: "HEAD", worktreePath: path))

        try "staged\n".write(toFile: path + "/kept.txt", atomically: true, encoding: .utf8)
        try "later\n".write(toFile: path + "/later.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "kept.txt", "later.txt"], in: path)
        let index = try await TestSupport.runGit(["write-tree"], in: path).standardOutput
        try "unstaged\n".write(toFile: path + "/kept.txt", atomically: true, encoding: .utf8)

        try await git.amend(
            worktreePath: path,
            excluding: ["README.md", "added.txt", "removed.txt"],
            message: "Keep one file",
            expectedHead: head,
        )

        #expect(await git.trackedFile(worktreePath: path, path: "README.md") == "hello\n")
        #expect(await git.trackedFile(worktreePath: path, path: "added.txt") == nil)
        #expect(await git.trackedFile(worktreePath: path, path: "removed.txt") == "old\n")
        #expect(await git.trackedFile(worktreePath: path, path: "kept.txt") == "kept\n")
        #expect(await git.trackedFile(worktreePath: path, path: "later.txt") == nil)
        #expect(await git.commitHash(of: "HEAD^", worktreePath: path) == parent)
        #expect(try await git.commitMessage(worktreePath: path, commit: "HEAD") == "Keep one file")
        #expect(try await TestSupport.runGit(["write-tree"], in: path).standardOutput == index)
        #expect(try String(contentsOfFile: path + "/README.md", encoding: .utf8) == "changed\n")
        #expect(try String(contentsOfFile: path + "/added.txt", encoding: .utf8) == "added\n")
        #expect(try String(contentsOfFile: path + "/kept.txt", encoding: .utf8) == "unstaged\n")
        #expect(FileManager.default.fileExists(atPath: path + "/removed.txt") == false)
    }

    @Test
    func `the root commit can exclude a literal path without matching a wildcard`() async throws {
        let path = try TestSupport.temporaryDirectory("uncommit-root")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        for file in ["file[1].txt", "file1.txt"] {
            try "added\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        }
        try await TestSupport.runGit(["add", "-A"], in: path)
        try await git.amend(worktreePath: path, message: "Initial files")
        #expect(await git.trackedFile(worktreePath: path, path: "file[1].txt") == "added\n")
        try await git.amend(
            worktreePath: path,
            excluding: ["file[1].txt"],
            message: "Keep the other files",
            expectedHead: #require(await git.commitHash(of: "HEAD", worktreePath: path)),
        )
        #expect(await git.trackedFile(worktreePath: path, path: "file[1].txt") == nil)
        #expect(await git.trackedFile(worktreePath: path, path: "file1.txt") == "added\n")
        #expect(await git.trackedFile(worktreePath: path, path: "README.md") == "hello\n")
        #expect(await git.commitHash(of: "HEAD^", worktreePath: path) == nil)
    }

    @Test
    func `excluding a rename restores both of its paths in the commit`() async throws {
        let path = try TestSupport.temporaryDirectory("uncommit-rename")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        try await TestSupport.runGit(["mv", "README.md", "renamed.md"], in: path)
        try "kept\n".write(toFile: path + "/kept.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: path, message: "Rename and add")
        try await git.amend(
            worktreePath: path,
            excluding: ["renamed.md"],
            message: "Only add",
            expectedHead: #require(await git.commitHash(of: "HEAD", worktreePath: path)),
        )
        #expect(await git.trackedFile(worktreePath: path, path: "README.md") == "hello\n")
        #expect(await git.trackedFile(worktreePath: path, path: "renamed.md") == nil)
        #expect(await git.trackedFile(worktreePath: path, path: "kept.txt") == "kept\n")
        #expect(try String(contentsOfFile: path + "/renamed.md", encoding: .utf8) == "hello\n")
        #expect(FileManager.default.fileExists(atPath: path + "/README.md") == false)
    }

    @Test
    func `a commit made after review refuses the amend`() async throws {
        let path = try TestSupport.temporaryDirectory("uncommit-stale")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let reviewed = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "new\n".write(toFile: path + "/new.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: path, message: "Newer work")
        let head = await git.commitHash(of: "HEAD", worktreePath: path)
        await #expect(throws: (any Error).self) {
            try await git.amend(
                worktreePath: path,
                excluding: ["README.md"],
                message: "Stale review",
                expectedHead: reviewed,
            )
        }
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == head)
    }
}
