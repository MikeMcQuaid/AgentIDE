import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises transcript reading against fixture JSONL files.
struct TranscriptReaderTests {
    @Test
    func `finds the newest transcript and its final assistant message`() throws {
        let directory = try TestSupport.temporaryDirectory("transcripts")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let older = directory + "/11111111-aaaa.jsonl"
        let newer = directory + "/22222222-bbbb.jsonl"
        let lines = """
        {"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}
        not even json
        {"type":"assistant","message":{"content":[{"type":"text","text":"first"},{"type":"text","text":"second"}]}}
        {"type":"system"}
        """
        try "{}\n".write(toFile: older, atomically: true, encoding: .utf8)
        try lines.write(toFile: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: older,
        )

        let reader = TranscriptReader()
        let latest = try #require(reader.latestTranscript(in: directory))
        #expect(latest.lastPathComponent == "22222222-bbbb.jsonl")
        #expect(reader.resumeID(of: latest) == "22222222-bbbb")
        #expect(reader.finalAssistantMessage(in: latest) == "first\nsecond")
    }

    @Test
    func `lists sessions newest first with prompt titles`() throws {
        let directory = try TestSupport.temporaryDirectory("sessions")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let older = directory + "/aaaa.jsonl"
        let newer = directory + "/bbbb.jsonl"
        try #"{"type":"user","message":{"content":[{"type":"text","text":"fix the\ncrash"}]}}"#
            .write(toFile: older, atomically: true, encoding: .utf8)
        try #"{"type":"user","message":{"content":[{"type":"text","text":"add tests"}]}}"#
            .write(toFile: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: older,
        )

        let sessions = TranscriptReader().sessions(in: directory, agent: .claudeCode)
        #expect(sessions.map(\.id) == ["bbbb", "aaaa"])
        #expect(sessions.first?.title == "add tests")
        #expect(sessions.last?.title == "fix the crash")
        #expect(sessions.allSatisfy { $0.agent == .claudeCode })
    }

    @Test
    func `parses a conversation into log entries with tool commands`() throws {
        let directory = try TestSupport.temporaryDirectory("entries")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = directory + "/cccc.jsonl"
        let lines = """
        {"type":"user","message":{"content":[{"type":"text","text":"do it"}]}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash",\
        "input":{"command":"git status"}}]}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read",\
        "input":{"file_path":"/tmp/a.txt"}}]}}
        garbage line
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task"}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}
        """
        try lines.write(toFile: transcript, atomically: true, encoding: .utf8)

        let entries = TranscriptReader().entries(in: URL(fileURLWithPath: transcript))
        #expect(entries.map(\.role) == [.user, .tool, .tool, .tool, .assistant])
        #expect(entries.map(\.text) == ["do it", "Bash: git status", "Read: /tmp/a.txt", "Task", "done"])
    }
}
