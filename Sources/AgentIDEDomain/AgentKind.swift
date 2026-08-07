/// A supported agent CLI, identified by its executable name.
public enum AgentKind: String, CaseIterable, Sendable {
    /// Anthropic's Claude Code CLI.
    case claudeCode = "claude"
    /// OpenAI's Codex CLI.
    case codexCLI = "codex"
}
