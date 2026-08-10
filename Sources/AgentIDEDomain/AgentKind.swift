/// A supported agent CLI, identified by its executable name.
public enum AgentKind: String, CaseIterable, Codable, Sendable {
    /// Anthropic's Claude Code CLI.
    case claudeCode = "claude"
    /// OpenAI's Codex CLI.
    case codexCLI = "codex"

    // MARK: Public

    /// The capitalised name shown in the UI; the raw value stays
    /// lowercase because session names embed it.
    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude"

        case .codexCLI:
            "Codex"
        }
    }

    /// The SF Symbol shown beside the agent's name.
    public var iconSystemName: String {
        switch self {
        case .claudeCode:
            "sparkles"

        case .codexCLI:
            "curlybraces.square"
        }
    }
}
