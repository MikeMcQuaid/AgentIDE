// MARK: - TranscriptSession

/// A past agent conversation discovered from its transcript file,
/// whoever created it.
public struct TranscriptSession: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a record of a discovered transcript; `resumeID`
    /// defaults to the id for agents whose file name is the resume
    /// handle.
    public init(id: String, path: String, agent: AgentKind, modifiedAt: Int, title: String, resumeID: String? = nil) {
        self.id = id
        self.path = path
        self.agent = agent
        self.modifiedAt = modifiedAt
        self.title = title
        self.resumeID = resumeID ?? id
    }

    // MARK: Public

    /// The transcript's file name stem. Unique per file, unlike
    /// Codex's embedded session id, which subagent rollouts share
    /// with their parent thread.
    public let id: String

    /// What the agent's resume flag takes: the file name stem for
    /// per-directory transcripts, Codex's embedded session id.
    public let resumeID: String

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
