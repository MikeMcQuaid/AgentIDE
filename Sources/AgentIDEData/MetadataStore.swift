import AgentIDEDomain
import Foundation

// MARK: - AppMetadata

/// The app-owned metadata that cannot be derived from the system.
public struct AppMetadata: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates empty metadata.
    public init() {
        // Every property has a default.
    }

    // MARK: Public

    /// When each session was last seen by the user, for unread state.
    public var lastSeen: [String: Date] = [:]

    /// The prompt each session was started with.
    public var prompts: [String: String] = [:]

    /// The extra agent arguments each session was started with.
    public var arguments: [String: String] = [:]

    /// The session name last launched in each worktree, so a closed
    /// session can be resumed without a live tmux session to name it.
    public var sessionsByWorktree: [String: String] = [:]

    /// The agent-native resume id last observed per session.
    public var resumeIDs: [String: String] = [:]

    /// Archives of deleted worktrees, newest last.
    public var archives: [ArchiveMetadata] = []
}

// MARK: - MetadataStore

/// Loads and saves the metadata file. Everything else re-derives from
/// tmux, git, transcripts and GitHub, so losing this file loses only
/// unread state, prompts and the archive index.
public struct MetadataStore: Sendable {
    // MARK: Lifecycle

    /// Creates a store at a file path.
    public init(file: String) {
        self.file = file
    }

    // MARK: Public

    /// Loads the metadata, empty when absent or unreadable.
    public func load() -> AppMetadata {
        guard let data = FileManager.default.contents(atPath: file) else {
            return AppMetadata()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppMetadata.self, from: data)) ?? AppMetadata()
    }

    /// Saves the metadata, creating parent directories as needed.
    public func save(_ metadata: AppMetadata) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata) else {
            return
        }

        let url = URL(fileURLWithPath: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Private

    private let file: String
}
