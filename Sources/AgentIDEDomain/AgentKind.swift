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

    /// The vendored brand mark shown beside the agent's name.
    public var iconAssetName: String {
        switch self {
        case .claudeCode:
            "agent-claude"

        case .codexCLI:
            "agent-codex"
        }
    }

    /// The mark's coloured form, for the connected state: Claude's
    /// is already coloured, while Codex's base asset is a template
    /// and needs the tinted variant to read as "in colour".
    public var connectedIconAssetName: String {
        switch self {
        case .claudeCode:
            "agent-claude"

        case .codexCLI:
            "agent-codex-colour"
        }
    }
}
