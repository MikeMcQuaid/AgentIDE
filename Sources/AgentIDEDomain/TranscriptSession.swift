// MARK: - TranscriptSession

/// A past agent conversation discovered from its transcript file,
/// whoever created it.
public struct TranscriptSession: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a record of a discovered transcript.
    public init(id: String, path: String, agent: AgentKind, modifiedAt: Int, title: String) {
        self.id = id
        self.path = path
        self.agent = agent
        self.modifiedAt = modifiedAt
        self.title = title
    }

    // MARK: Public

    /// The agent-native session id, the transcript's file name stem.
    public let id: String

    /// The transcript file's absolute path.
    public let path: String

    /// The agent that owns the transcript.
    public let agent: AgentKind

    /// When the transcript was last written, in seconds since 1970;
    /// an `Int` keeps this type free of Foundation.
    public let modifiedAt: Int

    /// The first user prompt, trimmed for display.
    public let title: String
}

// MARK: - TranscriptEntry

/// One displayable step of a conversation log.
public struct TranscriptEntry: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a log entry.
    public init(id: Int, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    // MARK: Public

    /// Who produced the entry.
    public enum Role: Hashable, Sendable {
        /// The human's prompt.
        case user
        /// The agent's reply text.
        case assistant
        /// A tool invocation, summarised by name.
        case tool
    }

    /// The entry's position in the transcript.
    public let id: Int

    /// Who produced the entry.
    public let role: Role

    /// The displayable text.
    public let text: String
}
