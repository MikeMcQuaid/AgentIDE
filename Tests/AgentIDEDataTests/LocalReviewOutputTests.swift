@testable import AgentIDEData
import Testing

struct LocalReviewOutputTests {
    @Test
    func `only the completed structured result becomes review findings`() throws {
        let output = #"{"type":"result","is_error":false,"structured_output":{"findings":[]}}"#
        #expect(try ClaudeCodeRunner().reviewOutput(output + "\n") == #"{"findings":[]}"#)
        let command = ClaudeCodeRunner().reviewCommand(
            executable: "/claude", promptFile: "/input", schemaFile: "/schema",
        )
        #expect(command.contains("'--output-format' 'json'"))
    }

    @Test(arguments: [
        #"{"type":"stream_event","structured_output":{"findings":[]}}"#,
        #"{"type":"result","is_error":true,"structured_output":{"findings":[]}}"#,
        #"{"type":"result","is_error":false}"#,
        "truncated JSON",
    ])
    func `a partial or failed final event never becomes findings`(ending: String) {
        #expect(throws: (any Error).self) { try ClaudeCodeRunner().reviewOutput(ending) }
    }
}
