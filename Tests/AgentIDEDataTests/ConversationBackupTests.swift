@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// The one thing the sandbox holds that git and GitHub do not: the
/// conversation. These pin that a copy is kept, refreshed and thrown
/// away with the worktree it belongs to.
struct ConversationBackupTests {
    // MARK: Internal

    @Test
    func `the newest conversation is copied, refreshed and forgotten`() throws {
        let root = try TestSupport.temporaryDirectory("backup")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let backup = ConversationBackup(paths: paths(root: root), directory: root + "/cloud")
        let worktree = Worktree(
            repositoryName: "platform",
            repositoryPath: root + "/platform",
            branch: "zendesk-sla-alignment",
            path: root + "/worktrees/uuid/polite-index",
        )
        let transcript = root + "/rollout.jsonl"
        try "first\n".write(toFile: transcript, atomically: true, encoding: .utf8)
        let past = TranscriptSession(
            id: "019ff168",
            path: transcript,
            agent: .codexCLI,
            modifiedAt: 0,
            title: "Align Zendesk SLA",
            resumeID: "019ff168",
        )

        backup.store(past, worktree: worktree)
        let copied = root + "/cloud/platform-zendesk-sla-alignment/conversation.jsonl"
        #expect(try String(contentsOfFile: copied, encoding: .utf8) == "first\n")

        // A conversation that has moved on replaces its copy, so what
        // is kept is what a resume would continue.
        try "first\nsecond\n".write(toFile: transcript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(Self.laterSeconds)],
            ofItemAtPath: transcript,
        )
        backup.store(past, worktree: worktree)
        #expect(try String(contentsOfFile: copied, encoding: .utf8) == "first\nsecond\n")

        // What it belongs to travels with it, since a conversation
        // file alone cannot say which worktree or agent it came from.
        let index = root + "/cloud/platform-zendesk-sla-alignment/conversation.json"
        let described = try #require(try? String(contentsOfFile: index, encoding: .utf8))
        #expect(described.contains("zendesk-sla-alignment"))
        #expect(described.contains("019ff168"))

        // Deleting the worktree is deliberate, so the copy goes too.
        backup.forget(worktree: worktree)
        #expect(FileManager.default.fileExists(atPath: copied) == false)
    }

    // MARK: Private

    /// Far enough ahead that the copy is unambiguously older.
    private static let laterSeconds = 60.0

    private func paths(root: String) -> WorkspacePaths {
        WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root + "/shared",
            sandboxHome: root + "/home",
            metadataFile: root + "/state.json",
            appDirectory: root + "/app",
        )
    }
}
