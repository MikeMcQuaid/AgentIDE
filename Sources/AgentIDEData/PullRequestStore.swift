import AgentIDEDomain
import Foundation

/// Everything the app asks GitHub about pull requests goes through
/// here, and every answer is remembered with the moment it arrived.
/// One pull request is never asked about twice inside a minute
/// however much clicking happens, and because the moments are kept
/// in the metadata file rather than in a view's memory, quitting and
/// relaunching does not start the asking over.
///
/// The values live in the caches they always did; what this owns is
/// the decision to ask at all. Acting on a pull request, rather than
/// looking at one, clears its stamp so the next read sees the truth.
public struct PullRequestStore: Sendable {
    // MARK: Lifecycle

    /// Creates the store over the GitHub client and the metadata
    /// file the whole app shares.
    public init(github: GitHubClient, store: MetadataStore) {
        self.github = github
        self.store = store
    }

    // MARK: Public

    /// The shortest time between two questions about the same pull
    /// request. Callers may ask for longer, never for less.
    public static let minimumInterval: TimeInterval = 60

    /// How long a repository's settings are taken at their word.
    public static let capabilityInterval: TimeInterval = 3_600

    /// A branch or scope's listing, fetched only when it is due;
    /// otherwise the last answer, which is what the tab paints.
    public func listing(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        limit: Int = GitHubClient.listLimit,
        interval: TimeInterval = minimumInterval,
    ) async throws -> [PullRequestSummary] {
        let key = Self.listingKey(repositoryPath: repositoryPath, scope: scope)
        guard let fresh = try await listingIfDue(
            repositoryPath: repositoryPath,
            scope: scope,
            limit: limit,
            interval: interval,
        ) else {
            return store.load().pullRequestListsCache[key]?.summaries ?? []
        }

        return fresh
    }

    /// The same listing, but nil rather than the cache when the last
    /// answer is still young: the sidebar's poll wants to know
    /// whether it learned anything.
    public func listingIfDue(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        limit: Int = GitHubClient.listLimit,
        interval: TimeInterval = minimumInterval,
        // Optional on purpose: nil means "asked too recently", which
        // the poll treats differently from an empty listing.
        // swiftlint:disable:next discouraged_optional_collection
    ) async throws -> [PullRequestSummary]? {
        let key = Self.listingKey(repositoryPath: repositoryPath, scope: scope)
        guard due(key, interval: interval) else {
            return nil
        }

        let fetched = try await github.pullRequests(repositoryPath: repositoryPath, scope: scope, limit: limit)
        var metadata = store.load()
        metadata.pullRequestListsCache[key] = CachedPullRequestList(summaries: fetched)
        metadata.fetchedAt[key] = Date()
        store.save(metadata)
        return fetched
    }

    /// Remembers a listing fetched elsewhere, so it answers later
    /// reads and holds off later fetches like the store's own.
    public func rememberListing(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        summaries: [PullRequestSummary],
    ) {
        var metadata = store.load()
        metadata.pullRequestListsCache[Self.listingKey(repositoryPath: repositoryPath, scope: scope)] =
            CachedPullRequestList(summaries: summaries)
        metadata.fetchedAt[Self.listingKey(repositoryPath: repositoryPath, scope: scope)] = Date()
        store.save(metadata)
    }

    /// The last full summary without asking anything.
    public func cachedSummary(repositoryPath: String, number: Int) -> PullRequestSummary? {
        store.load()
            .enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: number)]?
            .summary
    }

    /// Remembers a summary fetched elsewhere.
    public func rememberSummary(repositoryPath: String, summary: PullRequestSummary) {
        var metadata = store.load()
        metadata.enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: summary.number)] =
            CachedSummary(summary: summary)
        store.save(metadata)
    }

    /// The last listing without asking anything, for painting before
    /// a fetch has answered.
    public func cachedListing(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        // Optional on purpose: no cache yet paints a loading state,
        // an empty listing paints "No pull requests".
        // swiftlint:disable:next discouraged_optional_collection
    ) -> [PullRequestSummary]? {
        store.load()
            .pullRequestListsCache[Self.listingKey(repositoryPath: repositoryPath, scope: scope)]?
            .summaries
    }

    /// One pull request's full summary, with the expensive fields.
    public func summary(
        repositoryPath: String,
        number: Int,
        interval: TimeInterval = minimumInterval,
    ) async throws -> PullRequestSummary? {
        let key = Self.summaryKey(repositoryPath: repositoryPath, number: number)
        guard due(key, interval: interval) else {
            return store.load().enrichedSummaryCache[key]?.summary
        }

        let fetched = try await github.pullRequestSummary(repositoryPath: repositoryPath, number: number)
        guard let fetched else {
            return store.load().enrichedSummaryCache[key]?.summary
        }

        var metadata = store.load()
        metadata.enrichedSummaryCache[key] = CachedSummary(summary: fetched)
        metadata.fetchedAt[key] = Date()
        store.save(metadata)
        return fetched
    }

    /// Which of a repository's pull requests are in its merge queue.
    /// Kept in the metadata file like the rest, so a relaunch shows
    /// the queue it last saw rather than asking again at once.
    public func queuedNumbers(
        repositoryPath: String,
        interval: TimeInterval = minimumInterval,
    ) async -> Set<Int> {
        let key = "queue#" + repositoryPath
        guard due(key, interval: interval) else {
            return Set(store.load().queuedCache[repositoryPath] ?? [])
        }

        let fetched = await github.queuedNumbers(repositoryPath: repositoryPath)
        var metadata = store.load()
        metadata.queuedCache[repositoryPath] = fetched.sorted()
        metadata.fetchedAt[key] = Date()
        store.save(metadata)
        return fetched
    }

    /// Whether the repository merges through a queue, which changes
    /// about as often as its settings do; asked once an hour rather
    /// than on every visit to the tab.
    public func hasMergeQueue(
        repositoryPath: String,
        interval: TimeInterval = capabilityInterval,
    ) async -> Bool {
        let key = "queue-capability#" + repositoryPath
        guard due(key, interval: interval) else {
            return store.load().mergeQueueCapability[repositoryPath] ?? false
        }

        let answer = await github.hasMergeQueue(repositoryPath: repositoryPath)
        var metadata = store.load()
        metadata.mergeQueueCapability[repositoryPath] = answer
        metadata.fetchedAt[key] = Date()
        store.save(metadata)
        return answer
    }

    /// Forgets when one pull request was last asked about, so the
    /// next read asks again: what merging, queueing or resolving a
    /// conversation did must show at once, and none of those are
    /// clicking around.
    public func invalidate(repositoryPath: String, number: Int) {
        var metadata = store.load()
        for key in [
            Self.summaryKey(repositoryPath: repositoryPath, number: number),
            Self.conversationKey(repositoryPath: repositoryPath, number: number),
            "queue#" + repositoryPath,
        ] {
            metadata.fetchedAt.removeValue(forKey: key)
        }
        store.save(metadata)
    }

    /// Forgets a repository's listings, for what pushing a branch or
    /// opening a pull request has just changed.
    public func invalidateListings(repositoryPath: String) {
        var metadata = store.load()
        metadata.fetchedAt = metadata.fetchedAt.filter { entry in
            entry.key.hasPrefix("list#" + repositoryPath + "#") == false
        }
        store.save(metadata)
    }

    // MARK: Internal

    /// Internal so the conversation half, which lives in its own
    /// file for length, shares them.
    let github: GitHubClient
    let store: MetadataStore

    static func listingKey(repositoryPath: String, scope: GitHubClient.ListScope) -> String {
        "list#" + repositoryPath + "#" + String(describing: scope)
    }

    static func summaryKey(repositoryPath: String, number: Int) -> String {
        "summary#" + repositoryPath + "#" + String(number)
    }

    static func conversationKey(repositoryPath: String, number: Int) -> String {
        "conversation#" + repositoryPath + "#" + String(number)
    }

    /// Whether enough time has passed to ask again. A caller asking
    /// for less than the floor gets the floor.
    func due(_ key: String, interval: TimeInterval) -> Bool {
        guard let last = store.load().fetchedAt[key] else {
            return true
        }

        return Date().timeIntervalSince(last) >= max(interval, Self.minimumInterval)
    }
}
