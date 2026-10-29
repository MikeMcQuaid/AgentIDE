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
    /// file the whole app shares. `onBattery` says whether the
    /// machine is on battery, which slows every tier; injected so a
    /// test is not at the mercy of the machine it runs on.
    @preconcurrency
    public init(
        github: GitHubClient,
        store: MetadataStore,
        onBattery: @escaping @Sendable () -> Bool = { PowerSource.isOnBattery },
    ) {
        self.github = github
        self.store = store
        self.onBattery = onBattery
    }

    // MARK: Public

    /// The shortest time between two questions about the same pull
    /// request. Callers may ask for longer, never for less, except
    /// for the one-pull-request question, where a caller watching
    /// checks run or a queue move may ask down to `inFlightFloor`.
    public static let minimumInterval: TimeInterval = 60

    /// The floor for a single pull request's summary.
    public static let inFlightFloor: TimeInterval = 30

    /// How long a repository's settings are taken at their word:
    /// a day, since they change about as often as its settings do.
    public static let capabilityInterval: TimeInterval = 86_400

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
        return try await Self.listingReads.run(key: [store.file, key, String(limit)]) {
            try await readListingIfDue(repositoryPath: repositoryPath, scope: scope, limit: limit, interval: interval)
        }
    }

    /// The pull request a branch is showing, as the sidebar's rows
    /// and the pull request pane both read it: one structure, so a
    /// pull request opened in the pane appears on the row without
    /// either side telling the other.
    public func branchSummary(repositoryPath: String, branch: String) -> PullRequestSummary? {
        store.load().pullRequestCache[Self.branchKey(repositoryPath: repositoryPath, branch: branch)]
    }

    /// The last full summary without asking anything.
    public func cachedSummary(repositoryPath: String, number: Int) -> PullRequestSummary? {
        store.load()
            .enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: number)]?
            .summary
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
        return try await Self.summaryReads.run(key: [store.file, key]) {
            let cached = store.load().enrichedSummaryCache[key]?.summary
            guard due(key, interval: interval, floor: Self.inFlightFloor) || cached?.checkDetails == nil else {
                return cached
            }

            var fetched = try await github.pullRequestSummary(
                repositoryPath: repositoryPath,
                number: number,
                requiredChecks: requiredChecksReader(repositoryPath: repositoryPath),
            )
            guard let summary = fetched else {
                return store.load().enrichedSummaryCache[key]?.summary
            }

            fetched = await withStateChange(summary, previous: cached, repositoryPath: repositoryPath)

            store.update { metadata in
                fetched = fetched.map { Self.painted($0, repositoryPath: repositoryPath, in: &metadata) }
                guard let fetched else {
                    return
                }

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
    }

    /// How long a pull request's checks have been seen running, nil
    /// when they are not.
    public func pendingFor(repositoryPath: String, number: Int) -> TimeInterval? {
        store.load()
            .pendingSince[Self.summaryKey(repositoryPath: repositoryPath, number: number)]
            .map { Date().timeIntervalSince($0) }
    }

    /// Whether the repository merges through a queue, which changes
    /// about as often as its settings do; asked once a day rather
    /// than on every visit to the tab.
    public func hasMergeQueue(
        repositoryPath: String,
        interval: TimeInterval = capabilityInterval,
    ) async -> Bool {
        let key = "queue-capability#" + repositoryPath
        return await (try? Self.capabilityReads.run(key: [store.file, key]) {
            guard due(key, interval: interval) else {
                return store.load().mergeQueueCapability[repositoryPath] ?? false
            }

            let answer = await github.hasMergeQueue(repositoryPath: repositoryPath)
            store.update { metadata in
                metadata.mergeQueueCapability[repositoryPath] = answer
                metadata.fetchedAt[key] = Date()
            }
            return answer
        }) ?? false
    }

    /// Every repository's merge queue, those due asked for in one
    /// query and the rest answered from what they last said.
    public func queuedNumbers(
        repositoryPaths: [String],
        interval: TimeInterval = minimumInterval,
    ) async -> [String: Set<Int>] {
        var remaining = Set(repositoryPaths.filter { path in
            due("queue#" + path, interval: interval, floor: Self.inFlightFloor)
        })
        while remaining.isEmpty == false {
            let paths = remaining.sorted()
            let read = await (try? Self.queueReads.run(key: [store.file]) {
                await readQueuedNumbers(repositoryPaths: paths, interval: interval)
                return paths
            }) ?? paths
            // A pane can join the sidebar's batch; repositories absent
            // from that batch are checked once it has finished.
            remaining.subtract(read)
        }
        let queued = store.load().queuedCache
        return Dictionary(uniqueKeysWithValues: Set(repositoryPaths).map { ($0, Set(queued[$0] ?? [])) })
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
    let onBattery: @Sendable () -> Bool
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
                // Every tier, floors included, is five times longer on
                // battery: a check still running is still running.
                Date().timeIntervalSince(last)
                    >= RefreshCadence.slowed(max(interval, floor), onBattery: onBattery())
            } else {
                true
            }
        PerformanceLog.record(cacheHit: isDue == false, key)
        return isDue
    }
}
