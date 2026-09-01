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
    /// request. Callers may ask for longer, never for less, except
    /// for the one-pull-request question, where a caller watching
    /// checks run or a queue move may ask down to `inFlightFloor`.
    public static let minimumInterval: TimeInterval = 60

    /// The floor for a single pull request's summary.
    public static let inFlightFloor: TimeInterval = 30

    /// How long a repository's settings are taken at their word.
    public static let capabilityInterval: TimeInterval = 3_600

    /// How often a listing nobody is looking at is asked for.
    public static let backgroundInterval: TimeInterval = 300

    /// The key both sides have always used, so a cache written by an
    /// earlier release still paints.
    public static func branchKey(repositoryPath: String, branch: String) -> String {
        repositoryPath + "#" + branch
    }

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

        // A branch listing, the question the sidebar asks most, goes
        // conditional: GitHub answers an unchanged one with a 304,
        // which costs no rate limit, and the cache is what it was.
        // The other scopes are GraphQL, which has no entity tags.
        if case let .branch(branch) = scope {
            // The tag goes back only while the listing it stamped is
            // still here: caches are capped and age out, and a 304
            // against a listing the app no longer holds would report
            // a branch as having no pull request at all, for as long
            // as GitHub's answer stayed the same.
            let held = store.load()
            let cached = held.pullRequestListsCache[key]?.summaries
            let answer = try await github.branchPullRequests(
                repositoryPath: repositoryPath,
                branch: branch,
                etag: cached == nil ? nil : held.etags[key],
            )
            switch answer {
            case .unchanged:
                store.update { $0.fetchedAt[key] = Date() }
                PerformanceLog.record(.cacheHit, "etag " + key, seconds: 0)
                return cached ?? []

            case let .changed(body, etag):
                let fetched = GitHubClient.summaries(fromRESTJSON: body)
                store.update { metadata in
                    metadata.pullRequestListsCache[key] = CachedPullRequestList(summaries: fetched)
                    metadata.etags[key] = etag
                    metadata.fetchedAt[key] = Date()
                }
                return fetched
            }
        }

        let fetched = try await github.pullRequests(repositoryPath: repositoryPath, scope: scope, limit: limit)
        store.update { metadata in
            metadata.pullRequestListsCache[key] = CachedPullRequestList(summaries: fetched)
            metadata.fetchedAt[key] = Date()
        }
        return fetched
    }

    /// Remembers a listing fetched elsewhere, so it answers later
    /// reads and holds off later fetches like the store's own.
    public func rememberListing(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        summaries: [PullRequestSummary],
    ) {
        store.update { metadata in
            metadata.pullRequestListsCache[Self.listingKey(repositoryPath: repositoryPath, scope: scope)] =
                CachedPullRequestList(summaries: summaries)
            metadata.fetchedAt[Self.listingKey(repositoryPath: repositoryPath, scope: scope)] = Date()
        }
    }

    /// The pull request a branch is showing, as the sidebar's rows
    /// and the pull request pane both read it: one structure, so a
    /// pull request opened in the pane appears on the row without
    /// either side telling the other.
    public func branchSummary(repositoryPath: String, branch: String) -> PullRequestSummary? {
        store.load().pullRequestCache[Self.branchKey(repositoryPath: repositoryPath, branch: branch)]
    }

    /// Records what a branch is showing; nil forgets it, which is
    /// what a branch whose pull request has gone gets.
    public func rememberBranchSummary(
        _ summary: PullRequestSummary?,
        repositoryPath: String,
        branch: String,
    ) {
        let key = Self.branchKey(repositoryPath: repositoryPath, branch: branch)
        store.update { metadata in
            if let summary {
                metadata.pullRequestCache[key] = summary
            } else {
                metadata.pullRequestCache.removeValue(forKey: key)
            }
        }
    }

    /// The last full summary without asking anything.
    public func cachedSummary(repositoryPath: String, number: Int) -> PullRequestSummary? {
        store.load()
            .enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: number)]?
            .summary
    }

    /// Remembers a summary fetched elsewhere.
    public func rememberSummary(repositoryPath: String, summary: PullRequestSummary) {
        store.update { metadata in
            metadata.enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: summary.number)] =
                CachedSummary(summary: summary)
        }
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
        guard due(key, interval: interval, floor: Self.inFlightFloor) else {
            return store.load().enrichedSummaryCache[key]?.summary
        }

        let fetched = try await github.pullRequestSummary(repositoryPath: repositoryPath, number: number)
        guard let fetched else {
            return store.load().enrichedSummaryCache[key]?.summary
        }

        store.update { metadata in
            metadata.enrichedSummaryCache[key] = CachedSummary(summary: fetched)
            metadata.fetchedAt[key] = Date()
            // The moment checks were first seen running, kept until they
            // finish, so a run stuck for an hour can be told from one
            // about to end.
            if fetched.checks == "PENDING" {
                metadata.pendingSince[key] = metadata.pendingSince[key] ?? Date()
            } else {
                metadata.pendingSince.removeValue(forKey: key)
            }
        }
        return fetched
    }

    /// How long a pull request's checks have been seen running, nil
    /// when they are not.
    public func pendingFor(repositoryPath: String, number: Int) -> TimeInterval? {
        store.load()
            .pendingSince[Self.summaryKey(repositoryPath: repositoryPath, number: number)]
            .map { Date().timeIntervalSince($0) }
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
        store.update { metadata in
            metadata.mergeQueueCapability[repositoryPath] = answer
            metadata.fetchedAt[key] = Date()
        }
        return answer
    }

    /// Every repository's merge queue, those due asked for in one
    /// query and the rest answered from what they last said.
    public func queuedNumbers(
        repositoryPaths: [String],
        interval: TimeInterval = minimumInterval,
    ) async -> [String: Set<Int>] {
        let queued = store.load().queuedCache
        // One batched query for every repository is cheap enough to
        // allow under the floor while something is queued.
        let due = repositoryPaths.filter { due("queue#" + $0, interval: interval, floor: Self.inFlightFloor) }
        var answers = [String: Set<Int>]()
        for path in repositoryPaths where due.contains(path) == false {
            answers[path] = Set(queued[path] ?? [])
        }
        guard due.isEmpty == false else {
            return answers
        }

        let fetched = await github.queuedNumbers(repositoryPaths: due)
        store.update { metadata in
            for (path, numbers) in fetched {
                metadata.queuedCache[path] = numbers.sorted()
                metadata.fetchedAt["queue#" + path] = Date()
            }
        }
        for (path, numbers) in fetched {
            answers[path] = numbers
        }
        return answers
    }

    /// Forgets when one pull request was last asked about, so the
    /// next read asks again: what merging, queueing or resolving a
    /// conversation did must show at once, and none of those are
    /// clicking around.
    public func invalidate(repositoryPath: String, number: Int) {
        store.update { metadata in
            for key in [
                Self.summaryKey(repositoryPath: repositoryPath, number: number),
                Self.conversationKey(repositoryPath: repositoryPath, number: number),
                "queue#" + repositoryPath,
            ] {
                metadata.fetchedAt.removeValue(forKey: key)
            }
        }
    }

    /// Forgets one branch's listing stamp and its pull requests'
    /// summary stamps, for what an agent's finished turn is assumed
    /// to have changed: the next look asks GitHub now rather than
    /// waiting out the branch's interval, while every other branch
    /// waits on. The cached answers stay, so the rows keep painting
    /// until the fresh ones land.
    public func invalidateBranch(repositoryPath: String, branch: String) {
        let listing = Self.listingKey(repositoryPath: repositoryPath, scope: .branch(branch))
        store.update { metadata in
            metadata.fetchedAt.removeValue(forKey: listing)
            for summary in metadata.pullRequestListsCache[listing]?.summaries ?? [] {
                metadata.fetchedAt.removeValue(
                    forKey: Self.summaryKey(repositoryPath: repositoryPath, number: summary.number),
                )
            }
        }
    }

    /// Forgets a repository's listings, for what pushing a branch or
    /// opening a pull request has just changed.
    public func invalidateListings(repositoryPath: String) {
        store.update { metadata in
            metadata.fetchedAt = metadata.fetchedAt.filter { entry in
                entry.key.hasPrefix("list#" + repositoryPath + "#") == false
            }
        }
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
    func due(_ key: String, interval: TimeInterval, floor: TimeInterval = minimumInterval) -> Bool {
        let isDue: Bool =
            if let last = store.load().fetchedAt[key] {
                Date().timeIntervalSince(last) >= max(interval, floor)
            } else {
                true
            }
        PerformanceLog.record(cacheHit: isDue == false, key)
        return isDue
    }
}
