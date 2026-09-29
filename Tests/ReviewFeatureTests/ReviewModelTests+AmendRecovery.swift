import AgentIDEData
import Foundation
@testable import ReviewFeature
import TerminalUI
import Testing

extension ReviewModelTests {
    @Test(arguments: [false, true], [false, true])
    func `amend refreshes a changed tip and reports only success`(editedMessage: Bool, newCommit: Bool) async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-amend-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        for file in ["README.md", "excluded.txt", "earlier.txt"] {
            try "reviewed\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        }
        try await git.commitAll(worktreePath: path, message: "Reviewed commit")
        let marker = "amend-recovery-" + UUID().uuidString
        let model = ReviewModel(worktreePath: path, repositoryName: marker, git: git)
        model.scope = .lastCommit
        await model.reload()
        model.setCommitting(false, path: "excluded.txt")
        model.setCommitting(false, path: "earlier.txt")
        if editedMessage {
            model.commitMessage = "My edited message"
        }
        for file in ["README.md", "excluded.txt", "newer.txt"] {
            try "newer\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        }
        if newCommit == false {
            try FileManager.default.removeItem(atPath: path + "/earlier.txt")
        }
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q"] + (newCommit ? [] : ["--amend"]) + ["-m", "Newer message"], in: path)
        let parent = await git.commitHash(of: "HEAD^", worktreePath: path)
        try "staged\n".write(toFile: path + "/staged.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "--", "staged.txt"], in: path)
        try "working\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)

        await model.amendLastCommit()

        #expect(model.isAmending == false)
        #expect(model.commitMessage == (editedMessage ? "My edited message" : "Newer message"))
        #expect(await git.commitHash(of: "HEAD^", worktreePath: path) == parent)
        #expect(await git.trackedFile(worktreePath: path, path: "excluded.txt") == (newCommit ? "reviewed\n" : nil))
        #expect(await git.trackedFile(worktreePath: path, path: "earlier.txt") == (newCommit ? "reviewed\n" : nil))
        #expect(await git.trackedFile(worktreePath: path, path: "README.md") == "newer\n")
        #expect(await git.trackedFile(worktreePath: path, path: "newer.txt") == "newer\n")
        #expect(await git.trackedFile(worktreePath: path, path: "staged.txt") == nil)
        #expect(try String(contentsOfFile: path + "/README.md", encoding: .utf8) == "working\n")
        #expect(try String(contentsOfFile: path + "/excluded.txt", encoding: .utf8) == "newer\n")
        let messages = ErrorLog.shared.entries.filter { $0.repository == marker }
        #expect(messages.count == 1)
        #expect(messages.first?.isError == false)
        #expect(messages.first?.message == marker + ": Amended the last commit.")
    }

    @Test
    func `a failed amend after refreshing reports the recovery failure once`() async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-amend-failure-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let marker = "amend-failure-" + UUID().uuidString
        let model = ReviewModel(worktreePath: path, repositoryName: marker, git: git)
        model.scope = .lastCommit
        await model.reload()
        model.commitMessage = "My edited message"
        try "newer\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: path, message: "Newer message")
        let head = await git.commitHash(of: "HEAD", worktreePath: path)
        try await runGit(["config", "commit.gpgsign", "true"], in: path)
        try await runGit(["config", "gpg.program", "/usr/bin/false"], in: path)

        await model.amendLastCommit()

        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == head)
        #expect(model.isAmending == false)
        #expect(model.commitMessage == "My edited message")
        #expect(model.status == nil)
        let messages = ErrorLog.shared.entries.filter { $0.repository == marker }
        #expect(messages.count == 1)
        #expect(messages.first?.isError == true)
        #expect(messages.first?.message.contains("Amend failed after refreshing the changed commit:") == true)
    }
}
