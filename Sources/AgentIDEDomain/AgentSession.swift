// MARK: - SessionStatus

/// The observed state of a herdr-hosted agent session.
public enum SessionStatus: Hashable, Sendable {
    /// The agent process is still running in its pane.
    case running
    /// The agent process exited, leaving the pane's shell behind.
    case finished
}

// MARK: - AgentSession

/// A herdr workspace session, either one AgentIDE created or a
/// foreign one.
public struct AgentSession: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a session record.
    public init(
        name: String,
        agent: AgentKind?,
        status: SessionStatus,
        workingDirectory: String?,
        paneID: String? = nil,
        version: String? = nil,
    ) {
        self.version = version
        self.name = name
        self.agent = agent
        self.status = status
        self.workingDirectory = workingDirectory
        self.paneID = paneID
    }

    // MARK: Public

    /// The workspace label, the session name.
    public let name: String

    /// The agent the session runs, when recognisable from the name.
    public let agent: AgentKind?

    /// Whether the session's process is running or finished.
    public let status: SessionStatus

    /// The pane's current working directory, when known.
    public let workingDirectory: String?

    /// The herdr id of the workspace's pane, the target terminals
    /// attach to; nil when no live pane is known.
    public let paneID: String?

    /// The agent CLI version this session started with, when it was
    /// recorded; upgrading the CLI does not change it, which is the
    /// point of showing it.
    public let version: String?

    /// The stable identity, the session name.
    public var id: String {
        name
    }
}
