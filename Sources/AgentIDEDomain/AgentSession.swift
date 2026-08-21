// MARK: - SessionStatus

/// The observed state of a tmux-hosted agent session.
public enum SessionStatus: Hashable, Sendable {
    /// The pane's process is still running.
    case running
    /// The pane's process exited with the given status, if known.
    case finished(Int?)
}

// MARK: - AgentSession

/// A tmux session, either one AgentIDE created or a foreign one.
public struct AgentSession: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a session record.
    public init(
        name: String,
        agent: AgentKind?,
        status: SessionStatus,
        workingDirectory: String?,
        version: String? = nil,
    ) {
        self.version = version
        self.name = name
        self.agent = agent
        self.status = status
        self.workingDirectory = workingDirectory
    }

    // MARK: Public

    /// The tmux session name.
    public let name: String

    /// The agent the session runs, when recognisable from the name.
    public let agent: AgentKind?

    /// Whether the session's process is running or finished.
    public let status: SessionStatus

    /// The pane's current working directory, when known.
    public let workingDirectory: String?

    /// The agent CLI version this session started with, when it was
    /// recorded; upgrading the CLI does not change it, which is the
    /// point of showing it.
    public let version: String?

    /// The stable identity, the tmux session name.
    public var id: String {
        name
    }
}
