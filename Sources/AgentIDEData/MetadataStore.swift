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
        pullRequestListsCache = try container
            .decodeIfPresent([String: CachedPullRequestList].self, forKey: .pullRequestListsCache) ?? [:]
        conversationCache = try container
            .decodeIfPresent([String: CachedConversation].self, forKey: .conversationCache) ?? [:]
        enrichedSummaryCache = try container
            .decodeIfPresent([String: CachedSummary].self, forKey: .enrichedSummaryCache) ?? [:]
        threadsCache = try container
            .decodeIfPresent([String: CachedThreads].self, forKey: .threadsCache) ?? [:]
        intentionallyClosed = try container
            .decodeIfPresent([String].self, forKey: .intentionallyClosed) ?? []
        pullRequestDrafts = try container
            .decodeIfPresent([String: PullRequestFormDraft].self, forKey: .pullRequestDrafts) ?? [:]
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

    /// Each repository and scope's last pull request listing, so the
    /// tab paints instantly in a new session while a fetch refreshes.
    public var pullRequestListsCache: [String: CachedPullRequestList] = [:]

    /// Each pull request's last conversation, keyed by repository
    /// path and number, painted instantly like the listings.
    public var conversationCache: [String: CachedConversation] = [:]

    /// Enriched pull request headers by `repositoryPath#number`, so
    /// reopening a conversation paints its status icons instantly.
    public var enrichedSummaryCache: [String: CachedSummary] = [:]

    /// Review conversation threads by `repositoryPath#number`, so a
    /// reopened conversation paints them instantly.
    public var threadsCache: [String: CachedThreads] = [:]

    /// Unfinished pull request text by `repositoryPath#branch`, so
    /// the creation form survives leaving the tab.
    public var pullRequestDrafts: [String: PullRequestFormDraft] = [:]

    /// Worktrees whose last session the user closed deliberately;
    /// automatic resumes leave them alone until a session starts
    /// there again.
    public var intentionallyClosed: [String] = []

    /// Drops the oldest cache entries beyond each cap, so the
    /// metadata file stays bounded however long the app runs.
    public mutating func enforceCacheCaps() {
        if conversationCache.count > Self.conversationCap {
            let newest = conversationCache
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.conversationCap)
            conversationCache = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        if pullRequestListsCache.count > Self.listingCap {
            let newest = pullRequestListsCache
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.listingCap)
            pullRequestListsCache = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        if enrichedSummaryCache.count > Self.conversationCap {
            let newest = enrichedSummaryCache
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.conversationCap)
            enrichedSummaryCache = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        if threadsCache.count > Self.conversationCap {
            let newest = threadsCache
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.conversationCap)
            threadsCache = Dictionary(uniqueKeysWithValues: Array(newest))
        }
    }

    // MARK: Private

    /// Enough for every recently visited conversation and listing
    /// without the file growing forever.
    private static let conversationCap = 80
    private static let listingCap = 40
}

// MARK: - PullRequestFormDraft

/// A branch's unfinished pull request text, kept so leaving the tab
/// and coming back does not lose the writing.
public struct PullRequestFormDraft: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates a draft.
    public init(title: String, body: String, template: String) {
        self.title = title
        self.body = body
        self.template = template
    }

    // MARK: Public

    /// The drafted title.
    public let title: String

    /// The drafted body.
    public let body: String

    /// The template as edited.
    public let template: String
}

// MARK: - CachedSummary

/// One enriched pull request header, stamped so the cap can evict
/// the oldest.
public struct CachedSummary: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached header stamped now by default.
    public init(summary: PullRequestSummary, savedAt: Date = Date()) {
        self.summary = summary
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The enriched summary.
    public let summary: PullRequestSummary

    /// When the header was cached.
    public let savedAt: Date
}

// MARK: - CachedThreads

/// One conversation's review threads, stamped so the cap can evict
/// the oldest.
public struct CachedThreads: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates cached threads stamped now by default.
    public init(threads: [ReviewThread], savedAt: Date = Date()) {
        self.threads = threads
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The conversation threads.
    public let threads: [ReviewThread]

    /// When the threads were cached.
    public let savedAt: Date
}

// MARK: - CachedPullRequestList

/// One repository scope's cached pull request listing, stamped so
/// the cap can evict the oldest.
public struct CachedPullRequestList: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached listing stamped now by default.
    public init(summaries: [PullRequestSummary], savedAt: Date = Date()) {
        self.summaries = summaries
        self.savedAt = savedAt
    }

    // MARK: Public

    /// The listing as fetched.
    public var summaries: [PullRequestSummary]

    /// When the listing was cached, for eviction.
    public var savedAt: Date
}

// MARK: - CachedConversation

/// One pull request's cached body and feedback timeline.
public struct CachedConversation: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates a cached conversation stamped now by default.
    public init(body: String = "", events: [ReviewComment] = [], savedAt: Date = Date()) {
        self.body = body
        self.events = events
        self.savedAt = savedAt
    }

    /// Decodes tolerantly: entries cached before the stamp existed
    /// count as oldest rather than failing the whole metadata load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        events = try container.decodeIfPresent([ReviewComment].self, forKey: .events) ?? []
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }

    // MARK: Public

    /// The pull request's description.
    public var body: String

    /// The reviews and comments, in fetched order.
    public var events: [ReviewComment]

    /// When the conversation was cached, for eviction.
    public var savedAt: Date
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

    /// Saves the metadata, creating parent directories as needed;
    /// the caches are capped first so the file never grows forever.
    public func save(_ metadata: AppMetadata) {
        var metadata = metadata
        metadata.enforceCacheCaps()
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
