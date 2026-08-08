import AgentIDEData
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
}
