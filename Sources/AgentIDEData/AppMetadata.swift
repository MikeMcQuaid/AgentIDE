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

    /// Whether it is a directory of your own rather than a worktree.
    public var isHostDirectory = false

    /// What the row said last time: uncommitted work, the commit
    /// counts, and whether a session was running in it, so the pane
    /// knows to wait for herdr rather than showing conversations.
    public var isDirty = false
    public var aheadOfUpstream: Int?
    public var aheadOfDefault: Int?
    public var behindDefault: Int?
    public var lastActivityAt = 0
    public var hasSession = false

    /// The stack the row's worktree held at the last reading: its
    /// base, its branches bottom first and which was checked out.
    /// Deriving one is a hundred git calls across a wide sidebar,
    /// and every launch was doing all of them in its first second.
    public var stackBase: String?
    public var stackBranches: [String] = []
    public var stackCheckedOut: String?
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

    /// The repository's default branch, when known.
    public var defaultBranch: String?

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
        conversationBackupAt = try container
            .decodeIfPresent([String: Date].self, forKey: .conversationBackupAt) ?? [:]
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
        agentVersions = try container.decodeIfPresent([String: String].self, forKey: .agentVersions) ?? [:]
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
        hostDirectories = try container
            .decodeIfPresent([String: [String]].self, forKey: .hostDirectories) ?? [:]
        stackExclusions = try container
            .decodeIfPresent([String: [String]].self, forKey: .stackExclusions) ?? [:]
        fetchedAt = try container.decodeIfPresent([String: Date].self, forKey: .fetchedAt) ?? [:]
        queuedCache = try container.decodeIfPresent([String: [Int]].self, forKey: .queuedCache) ?? [:]
        mergeQueueCapability = try container
            .decodeIfPresent([String: Bool].self, forKey: .mergeQueueCapability) ?? [:]
        discoveredModels = try container
            .decodeIfPresent([String: [String]].self, forKey: .discoveredModels) ?? [:]
        discoveredModelsVersion = try container
            .decodeIfPresent([String: String].self, forKey: .discoveredModelsVersion) ?? [:]
        etags = try container.decodeIfPresent([String: String].self, forKey: .etags) ?? [:]
        terminalSchemes = try container
            .decodeIfPresent([String: String].self, forKey: .terminalSchemes) ?? [:]
    }

    // MARK: Public

    /// Directories of your own listed under a repository: paths on
    /// the Mac that get a shell, an editor and a diff but never an
    /// agent, keyed by the repository they are listed under.
    public var hostDirectories: [String: [String]] = [:]

    /// When each pull request question was last put to GitHub, by
    /// the asking key. The whole app's timers, in one place and in
    /// the file, so no amount of clicking or relaunching asks about
    /// one pull request more than once a minute. See
    /// `PullRequestStore`, which is the only thing that writes here.
    public var fetchedAt: [String: Date] = [:]

    /// Each repository's merge queue at its last listing, kept so a
    /// relaunch shows the queue it knew rather than asking at once.
    public var queuedCache: [String: [Int]] = [:]

    /// Whether each repository merges through a queue at all.
    public var mergeQueueCapability: [String: Bool] = [:]

    /// The models each CLI last reported, by agent raw value, so the
    /// pickers open on a relaunch with the real list while the CLI
    /// is asked again in the background: asking took twenty seconds
    /// of sandbox launch on every start.
    public var discoveredModels: [String: [String]] = [:]

    /// The CLI version each model list came from: a list is asked
    /// for again only when the CLI has changed, since the answer
    /// cannot have.
    public var discoveredModelsVersion: [String: String] = [:]

    /// The entity tag GitHub last answered each REST listing with,
    /// by the listing's key. Sent back as `If-None-Match`, so a poll
    /// that finds nothing changed is one round trip and no rate
    /// limit, which is most polls.
    public var etags: [String: String] = [:]

    /// "dark" or "light" per worktree path: the appearance its agent
    /// was launched under. Agent TUIs read the terminal's colours
    /// once at startup and never again, so the pane must keep the
    /// palette the agent believes in for the session's whole life.
    public var terminalSchemes: [String: String] = [:]

    /// Branches a worktree's stack should leave out, by worktree
    /// path. The stack is inferred from ancestry, which cannot know
    /// that an old branch sharing history is nothing to do with the
    /// work in hand; this is where saying so is remembered.
    public var stackExclusions: [String: [String]] = [:]

    /// When each session was last seen by the user, for unread state.
    public var lastSeen: [String: Date] = [:]

    /// When each worktree path was last viewed, for unread state.
    public var seenAt: [String: Date] = [:]

    /// When each worktree's conversation was last copied out of the
    /// sandbox, so a long-running session is copied on a schedule
    /// rather than on every poll.
    public var conversationBackupAt: [String: Date] = [:]

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

    /// The CLI version each session started with, which stays what
    /// it was when the CLI is upgraded under a running session.
    public var agentVersions: [String: String] = [:]

    /// The session name last launched in each worktree, so a closed
    /// session can be resumed without a live workspace to name it.
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

    /// Where one pull request's conversations are cached. The pane
    /// that reads them and the sidebar that counts what is still
    /// unresolved have to agree on the key, so it is defined once.
    public static func threadsKey(repositoryPath: String, number: Int) -> String {
        repositoryPath + "#" + String(number)
    }

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
        // The ledger outlives every value it stamps, so it is
        // trimmed by age rather than by count: a stamp older than
        // the longest interval anything asks for can only say
        // "ask again", which is what its absence says too.
        let stale = Date().addingTimeInterval(-Self.stampLife)
        fetchedAt = fetchedAt.filter { $0.value > stale }
        // The dated caches age out at a week: a listing, header,
        // conversation or thread set unread for that long is not
        // worth the file it takes up.
        let old = Date().addingTimeInterval(-Self.cacheLife)
        pullRequestListsCache = pullRequestListsCache.filter { $0.value.savedAt > old }
        conversationCache = conversationCache.filter { $0.value.savedAt > old }
        enrichedSummaryCache = enrichedSummaryCache.filter { $0.value.savedAt > old }
        threadsCache = threadsCache.filter { $0.value.savedAt > old }
        if threadsCache.count > Self.conversationCap {
            let newest = threadsCache
                .sorted { $0.value.savedAt > $1.value.savedAt }
                .prefix(Self.conversationCap)
            threadsCache = Dictionary(uniqueKeysWithValues: Array(newest))
        }
    }

    // MARK: Private

    /// How long a fetch stamp is worth keeping: longer than the
    /// slowest poll interval, short enough that the file does not
    /// collect a line per pull request ever seen.
    private static let stampLife: TimeInterval = 86_400

    /// A week: how long a cached value is kept unread.
    private static let cacheLife: TimeInterval = 604_800

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
