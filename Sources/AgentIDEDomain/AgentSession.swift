// MARK: - AgentActivity

/// What a running agent is doing, as herdr's lifecycle detection
/// reports it.
public enum AgentActivity: Hashable, Sendable {
    /// The agent is actively running a turn.
    case working
    /// The agent is ready for input.
    case idle
    /// The agent is waiting on an approval or decision.
    case blocked

    // MARK: Lifecycle

    /// Maps herdr's status strings; `done` is herdr's own
    /// idle-but-unseen, which this app's seen tracking replaces, and
    /// `unknown` or absent statuses answer nil.
    public init?(herdrStatus: String?) {
        switch herdrStatus {
        case "working":
            self = .working

        case "done",
             "idle":
            self = .idle

        case "blocked":
            self = .blocked

        default:
            return nil
        }
    }
}

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
        activity: AgentActivity? = nil,
        version: String? = nil,
    ) {
        self.version = version
        self.name = name
        self.agent = agent
        self.status = status
        self.workingDirectory = workingDirectory
        self.paneID = paneID
        self.activity = activity
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

    /// What the agent is doing right now, when herdr can tell.
    public let activity: AgentActivity?

    /// The agent CLI version this session started with, when it was
    /// recorded; upgrading the CLI does not change it, which is the
    /// point of showing it.
    public let version: String?

    /// The stable identity, the session name.
    public var id: String {
        name
    }
}
