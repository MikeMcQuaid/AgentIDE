import AgentIDEDomain
import Foundation

// MARK: - CachedWorktree

/// A worktree in the sidebar snapshot rendered before the first poll.
public struct CachedWorktree: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates an empty entry.
    public init() {
        // Every property has a default.
    }

    // MARK: Public

    /// The branch checked out in the worktree.
    public var branch = ""

    /// The worktree's canonical path.
    public var path = ""
}

// MARK: - CachedRepository

/// A repository in the sidebar snapshot rendered before the first
/// poll.
public struct CachedRepository: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates an empty entry.
    public init() {
        // Every property has a default.
    }

    // MARK: Public

    /// The repository's directory name.
    public var name = ""

    /// The GitHub `owner/name`, when known.
    public var fullName: String?

    /// The checkout path.
    public var path = ""

    /// The repository's worktrees.
    public var worktrees: [CachedWorktree] = []
}

// MARK: - AppMetadata

/// The app-owned metadata that cannot be derived from the system.
/// Decoding tolerates missing keys so adding a field never discards
/// an existing file.
public struct AppMetadata: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates empty metadata.
    public init() {
        // Every property has a default.
    }

    /// Decodes tolerantly: absent keys keep their defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSeen = try container.decodeIfPresent([String: Date].self, forKey: .lastSeen) ?? [:]
        seenAt = try container.decodeIfPresent([String: Date].self, forKey: .seenAt) ?? [:]
        unreadMarks = try container.decodeIfPresent([String].self, forKey: .unreadMarks) ?? []
        pullRequestCache = try container
            .decodeIfPresent([String: PullRequestSummary].self, forKey: .pullRequestCache) ?? [:]
        organisations = try container
            .decodeIfPresent([String].self, forKey: .organisations) ?? []
        ownerRepositories = try container
            .decodeIfPresent([String: [String]].self, forKey: .ownerRepositories) ?? [:]
        openIssuesCache = try container
            .decodeIfPresent([String: [IssueSummary]].self, forKey: .openIssuesCache) ?? [:]
        openPullRequestsCache = try container
            .decodeIfPresent([String: [PullRequestSummary]].self, forKey: .openPullRequestsCache) ?? [:]
        prompts = try container.decodeIfPresent([String: String].self, forKey: .prompts) ?? [:]
        arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
        sessionsByWorktree = try container
            .decodeIfPresent([String: String].self, forKey: .sessionsByWorktree) ?? [:]
        resumeIDs = try container.decodeIfPresent([String: String].self, forKey: .resumeIDs) ?? [:]
        cachedSidebar = try container.decodeIfPresent([CachedRepository].self, forKey: .cachedSidebar) ?? []
    }

    // MARK: Public

    /// When each session was last seen by the user, for unread state.
    public var lastSeen: [String: Date] = [:]

    /// When each worktree path was last viewed, for unread state.
    public var seenAt: [String: Date] = [:]

    /// Worktree paths the user marked unread to revisit, cleared by
    /// viewing them.
    public var unreadMarks: [String] = []

    /// Each branch's last known pull request, keyed by repository
    /// path and branch, so badges survive restarts and green results
    /// for an unchanged commit need no refetch.
    public var pullRequestCache: [String: PullRequestSummary] = [:]

    /// The user's login and organisations at last listing, so the
    /// repository finder's owner step opens instantly.
    public var organisations: [String] = []

    /// Each owner's repositories at last listing, keyed by owner, so
    /// the finder's second step paints instantly.
    public var ownerRepositories: [String: [String]] = [:]

    /// Each repository's open issues at last listing, for instant
    /// pickers, keyed by repository path.
    public var openIssuesCache: [String: [IssueSummary]] = [:]

    /// Each repository's open pull requests at last listing, for
    /// instant pickers, keyed by repository path.
    public var openPullRequestsCache: [String: [PullRequestSummary]] = [:]

    /// The prompt each session was started with.
    public var prompts: [String: String] = [:]

    /// The extra agent arguments each session was started with.
    public var arguments: [String: String] = [:]

    /// The session name last launched in each worktree, so a closed
    /// session can be resumed without a live tmux session to name it.
    public var sessionsByWorktree: [String: String] = [:]

    /// The agent-native resume id last observed per session.
    public var resumeIDs: [String: String] = [:]

    /// The last rendered sidebar, so a fresh launch paints instantly
    /// while the first poll runs.
    public var cachedSidebar: [CachedRepository] = []
}

// MARK: - MetadataStore

/// Loads and saves the metadata file. Everything else re-derives from
/// tmux, git, transcripts and GitHub, so losing this file loses only
/// unread state, prompts and orphaned worktree attribution.
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
