import Foundation

// MARK: - AgentActivity

/// What a running agent is doing, as herdr's lifecycle detection
/// reports it.
public enum AgentActivity: Codable, Hashable, Sendable {
    /// The agent is actively running a turn.
    case working
    /// The agent is at rest without a completed turn: never asked,
    /// or interrupted mid-answer.
    case idle
    /// The agent completed its turn; the answer is waiting.
    case done
    /// The agent is waiting on an approval or decision.
    case blocked

    // MARK: Lifecycle

    /// Maps herdr's status strings one to one; `unknown` or absent
    /// statuses answer nil, which the surfaces show as undetected.
    public init?(herdrStatus: String?) {
        switch herdrStatus {
        case "working":
            self = .working

        case "idle":
            self = .idle

        case "done":
            self = .done

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
        paneID: String? = nil,
        activity: AgentActivity? = nil,
        version: String? = nil,
        lastActivityAt: Date? = nil,
        now: Date = Date(),
    ) {
        self.version = version
        self.name = name
        self.agent = agent
        self.status = status
        self.paneID = paneID
        self.activity = activity
        self.lastActivityAt = lastActivityAt
        sidebarActivity = status == .running && activity == .done
            && lastActivityAt.map { now.timeIntervalSince($0) > Self.completedTurnLifetime } == true
            ? .idle : activity
    }

    // MARK: Public

    /// The workspace label, the session name.
    public let name: String

    /// The agent the session runs, when recognisable from the name.
    public let agent: AgentKind?

    /// Whether the session's process is running or finished.
    public let status: SessionStatus

    /// The herdr id of the workspace's pane, the target terminals
    /// attach to; nil when no live pane is known.
    public let paneID: String?

    /// What the agent is doing right now, when herdr can tell.
    public let activity: AgentActivity?

    /// Completed turns age into idle in the sidebar without changing
    /// the state used by herdr waits, notifications or automation.
    public let sidebarActivity: AgentActivity?

    /// The latest agent event, independent of viewing or refreshing it.
    public let lastActivityAt: Date?

    /// The agent CLI version this session started with, when it was
    /// recorded; upgrading the CLI does not change it, which is the
    /// point of showing it.
    public let version: String?

    /// The stable identity, the session name.
    public var id: String {
        name
    }

    /// Event recency decides the shared slot; priority breaks ties
    /// and readings whose clocks are unavailable.
    public func precedes(_ pullRequest: PullRequestSummary?) -> Bool {
        guard let pullRequest else {
            return true
        }

        if let lastActivityAt, let changedAt = pullRequest.stateChangedAt, lastActivityAt != changedAt {
            return lastActivityAt > changedAt
        }
        return status == .running && sidebarActivity.map { [.blocked, .working, .done].contains($0) } == true
    }

    // MARK: Private

    private static let completedTurnLifetime: TimeInterval = 86_400
}
