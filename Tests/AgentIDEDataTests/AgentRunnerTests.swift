import AgentIDEData
import Testing

/// Exercises the launch command assembly the prompt delivery relies
/// on, the successor to the deleted paste-delivery coverage.
struct AgentRunnerTests {
    @Test
    func `launch commands embed the prompt file shell-quoted`() {
        let command = ClaudeCodeRunner().launchCommand(
            extraArguments: "--model fable",
            promptFile: "/tmp/it's a prompt.md",
        )
        // The single quotes close, escape the apostrophe and reopen,
        // so a quote in the path cannot break out of the quoting.
        #expect(command == "claude --model fable \"$(cat '/tmp/it'\\''s a prompt.md')\"")
    }

    @Test
    func `launch commands without a prompt or arguments stay bare`() {
        #expect(CodexRunner().launchCommand(extraArguments: "  ", promptFile: nil) == "codex")
        #expect(ClaudeCodeRunner().resumeCommand(resumeID: "abc", extraArguments: "") == "claude --resume 'abc'")
    }
}
