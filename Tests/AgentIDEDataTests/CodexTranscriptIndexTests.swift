import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the Codex session index against fixture rollout files,
/// so worktrees keep listing and resuming Codex conversations even
/// though nothing on disk is keyed by working directory.
struct CodexTranscriptIndexTests {
    // MARK: Internal

    @Test
    func `indexes sessions by their embedded working directory`() throws {
        let root = try TestSupport.temporaryDirectory("codex-index")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let day = root + "/2026/08/12"
        try FileManager.default.createDirectory(atPath: day, withIntermediateDirectories: true)
        try write(
            to: day + "/rollout-newer.jsonl",
            cwd: "/worktrees/one",
            id: "session-new",
            message: "fix the crash\nwith details",
            modifiedAt: 2,
        )
        try write(
            to: day + "/rollout-older.jsonl",
            cwd: "/worktrees/one",
            id: "session-old",
            message: "add tests",
            modifiedAt: 1,
        )
        try write(
            to: day + "/rollout-elsewhere.jsonl",
            cwd: "/worktrees/two",
            id: "session-other",
            message: "other work",
            modifiedAt: 3,
        )
        // No metadata line: the file cannot be resumed, so it hides.
        try #"{"type":"response_item","payload":{"type":"user_message","message":"orphan"}}"#
            .write(toFile: day + "/rollout-broken.jsonl", atomically: true, encoding: .utf8)

        let sessions = CodexTranscriptIndex().sessions(inRoot: root, workingDirectory: "/worktrees/one")
        #expect(sessions.map(\.id) == ["session-new", "session-old"])
        #expect(sessions.first?.title == "fix the crash")
        #expect(sessions.allSatisfy { $0.agent == .codexCLI })
    }

    // MARK: Private

    /// Writes one rollout head in the real Codex shape: the metadata
    /// line carries the resume id and working directory, never the
    /// file name.
    private func write(to path: String, cwd: String, id: String, message: String, modifiedAt: Int) throws {
        let meta = #"{"type":"session_meta","payload":{"cwd":"\#(cwd)","id":"\#(id)"}}"#
        let prompt = #"{"type":"response_item","payload":{"type":"user_message","message":"\#(escaped(message))"}}"#
        try (meta + "\n" + prompt + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(modifiedAt))],
            ofItemAtPath: path,
        )
    }

    private func escaped(_ message: String) -> String {
        message.replacing("\n", with: "\\n")
    }
}
