@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the Codex session index against fixture rollout files,
/// so worktrees keep listing and resuming Codex conversations even
/// though nothing on disk is keyed by working directory.
struct CodexTranscriptIndexTests {
    // MARK: Internal

    @Test
    func `head decoding survives a cut inside a multi-byte character`() {
        let ellipsis = Array("…".utf8)
        let whole = Data(Array("line one\n".utf8) + ellipsis)
        #expect(CodexTranscriptIndex.decodeHead(whole) == "line one\n…")
        // A fixed-size read can end mid-character; the partial
        // trailing bytes drop rather than losing the whole session.
        let cut = whole.dropLast()
        #expect(CodexTranscriptIndex.decodeHead(Data(cut)) == "line one\n")
        #expect(CodexTranscriptIndex.decodeHead(Data()) != nil)
    }

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
        // A subagent rollout shares its parent's session id and cwd;
        // it is machinery, not a conversation, and stays hidden.
        let subagent = #"{"type":"session_meta","payload":"# +
            #"{"cwd":"/worktrees/one","id":"session-new","thread_source":"subagent"}}"#
        try (subagent + "\n").write(toFile: day + "/rollout-subagent.jsonl", atomically: true, encoding: .utf8)

        let sessions = CodexTranscriptIndex().sessions(inRoot: root, workingDirectory: "/worktrees/one")
        // The file stem is the row identity; the embedded session id
        // is what resume passes to Codex.
        #expect(sessions.map(\.id) == ["rollout-newer", "rollout-older"])
        #expect(sessions.map(\.resumeID) == ["session-new", "session-old"])
        #expect(sessions.first?.title == "fix the crash")
        #expect(sessions.allSatisfy { $0.agent == .codexCLI })
    }

    @Test
    func `titles current-generation rollouts by the typed prompt`() throws {
        let root = try TestSupport.temporaryDirectory("codex-index-current")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let day = root + "/2026/08/12"
        try FileManager.default.createDirectory(atPath: day, withIntermediateDirectories: true)
        // The current rollout generation: role-and-content messages,
        // with Codex's injected preamble before the typed prompt.
        let current = """
        {"type":"session_meta","payload":{"cwd":"/worktrees/three","id":"session-current"}}
        {"type":"response_item","payload":{"type":"message","role":"user",\
        "content":[{"type":"input_text","text":"# AGENTS.md instructions for /w\\ninjected"}]}}
        {"type":"response_item","payload":{"type":"message","role":"user",\
        "content":[{"type":"input_text","text":"ship the feature\\nplease"}]}}
        """
        try (current + "\n").write(toFile: day + "/rollout-current.jsonl", atomically: true, encoding: .utf8)

        let sessions = CodexTranscriptIndex().sessions(inRoot: root, workingDirectory: "/worktrees/three")
        #expect(sessions.map(\.id) == ["rollout-current"])
        #expect(sessions.map(\.resumeID) == ["session-current"])
        #expect(sessions.first?.title == "ship the feature")
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
