import AgentIDEDomain

// MARK: - AgentRunner

/// Everything agent-specific: how to launch, resume and find the
/// transcripts of one agent CLI. All other code speaks this seam.
/// Prompts are never passed as arguments; they arrive through the
/// terminal via tmux paste after launch.
public protocol AgentRunner: Sendable {
    /// The agent this runner drives.
    var kind: AgentKind { get }

    /// The shell command that starts the agent interactively, with
    /// caller-supplied extra arguments appended verbatim.
    func launchCommand(extraArguments: String) -> String

    /// The shell command that resumes a previous conversation.
    func resumeCommand(resumeID: String, extraArguments: String) -> String

    /// The directory holding transcripts for a working directory,
    /// nil when the agent has no discoverable transcripts.
    func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String?
}

extension AgentRunner {
    /// Joins a base command with verbatim extra arguments.
    func command(_ base: String, _ extraArguments: String) -> String {
        let trimmed = extraArguments.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? base : base + " " + trimmed
    }
}

// MARK: - ClaudeCodeRunner

/// Drives Anthropic's Claude Code CLI.
public struct ClaudeCodeRunner: AgentRunner {
    // MARK: Lifecycle

    /// Creates a runner.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// Claude Code.
    public var kind: AgentKind {
        .claudeCode
    }

    /// Starts Claude Code interactively; the sandbox's wrapper adds
    /// its permission flag.
    public func launchCommand(extraArguments: String) -> String {
        command("claude", extraArguments)
    }

    /// Resumes a conversation by its session id.
    public func resumeCommand(resumeID: String, extraArguments: String) -> String {
        command("claude --resume '" + resumeID + "'", extraArguments)
    }

    /// Claude Code keys transcript directories by the working
    /// directory with `/` and `.` replaced by `-`.
    public func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String? {
        let dashified = workingDirectory
            .replacing("/", with: "-")
            .replacing(".", with: "-")
        return sandboxHome + "/.claude/projects/" + dashified
    }
}

// MARK: - CodexRunner

/// Drives OpenAI's Codex CLI.
public struct CodexRunner: AgentRunner {
    // MARK: Lifecycle

    /// Creates a runner.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// Codex CLI.
    public var kind: AgentKind {
        .codexCLI
    }

    /// Starts Codex interactively.
    public func launchCommand(extraArguments: String) -> String {
        command("codex", extraArguments)
    }

    /// Resumes a conversation by its session id.
    public func resumeCommand(resumeID: String, extraArguments: String) -> String {
        command("codex resume '" + resumeID + "'", extraArguments)
    }

    /// Codex keeps a flat session directory per user.
    public func transcriptDirectory(workingDirectory _: String, sandboxHome: String) -> String? {
        sandboxHome + "/.codex/sessions"
    }
}
