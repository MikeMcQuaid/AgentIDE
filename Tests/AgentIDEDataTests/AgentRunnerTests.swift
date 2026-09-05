@testable import AgentIDEData
import Testing

/// Exercises the launch command assembly the prompt delivery relies
/// on, the successor to the deleted paste-delivery coverage.
struct AgentRunnerTests {
    @Test
    func `an agent with no listing offers its curated models and forgets what was scraped`() {
        // `claude models` is not a subcommand: Claude Code takes an
        // unknown argument as a prompt, so asking started a session
        // and the words of its answer were read as model names.
        #expect(ClaudeCodeRunner().modelListingCommand.isEmpty)
        #expect(ClaudeCodeRunner().models == ["fable", "opus", "sonnet", "haiku"])
        // Codex has a real listing to read, so it keeps one.
        #expect(CodexRunner().modelListingCommand.isEmpty == false)
    }

    @Test
    func `versions come out of whatever the CLI wraps them in`() {
        #expect(ClaudeCodeRunner().parseVersion("2.1.238 (Claude Code)") == "2.1.238")
        #expect(CodexRunner().parseVersion("codex-cli 0.149.0\n") == "0.149.0")
        #expect(CodexRunner().parseVersion("codex-cli v1.0\n") == "1.0")
        // Nothing version-shaped is no answer, never a stray word.
        #expect(ClaudeCodeRunner().parseVersion("command not found") == nil)
        #expect(ClaudeCodeRunner().parseVersion("") == nil)
    }

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

    @Test
    func `every agent offers something to start on`() {
        // A form opens on these: the first model the agent lists and
        // the effort the CLI itself runs at, which is not the first
        // of its tiers.
        let claude = ClaudeCodeRunner()
        #expect(claude.models.first == "fable")
        #expect(claude.defaultEffort == "high")
        #expect(claude.efforts.first == "max")

        let codex = CodexRunner()
        #expect(codex.models.first == "gpt-5.6-sol")
        #expect(codex.defaultEffort == "medium")
    }

    @Test
    func `a listing's placeholders are not models to pick`() {
        // Codex's cache names a reservation and the reviewer it runs
        // itself; neither is something to start a session on.
        let listed = """
        gpt-reserve
        gpt-5.6-sol
        codex-auto-review
        gpt-5.4-mini
        """
        #expect(CodexRunner().parseModelList(listed) == ["gpt-5.6-sol", "gpt-5.4-mini"])
    }
}
