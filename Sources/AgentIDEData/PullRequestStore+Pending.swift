import AgentIDEDomain
import Foundation

/// What a push paints into the caches before GitHub has seen it, and
/// how long it keeps painting it. Split from the store for length.
public extension PullRequestStore {
    /// Paints the pull requests of the pushed branches as awaiting
    /// their checks, in every cache a row or a pane reads, so the
    /// sidebar and the tab show pending the moment a push lands
    /// rather than the last run's verdict. The mark then outlives
    /// the paint: GitHub takes a minute to see the commits, and a
    /// listing fetched inside that minute still says what the old
    /// run did, so a fetched summary keeps being painted pending
    /// until GitHub reports a head commit other than the one it
    /// last reported, when its rollup is about the new commits.
    func markChecksPending(repositoryPath: String, branches: [String]) {
        let pushed = Set(branches)
        store.update { metadata in
            var numbers = Set<Int>()
            for branch in pushed {
                let key = Self.branchKey(repositoryPath: repositoryPath, branch: branch)
                let known = metadata.pullRequestCache[key]
                metadata.pendingChecks[key] = known?.headCommit ?? ""
                metadata.fetchedAt[Self.pendingKey(key)] = Date()
                guard let known else {
                    continue
                }

                metadata.pullRequestCache[key] = known.awaitingChecks()
                numbers.insert(known.number)
            }
            numbers.formUnion(Self.paintListings(of: pushed, repositoryPath: repositoryPath, in: &metadata))
            for number in numbers {
                let key = Self.summaryKey(repositoryPath: repositoryPath, number: number)
                if let cached = metadata.enrichedSummaryCache[key] {
                    metadata.enrichedSummaryCache[key] = CachedSummary(
                        summary: cached.summary.awaitingChecks(),
                        savedAt: cached.savedAt,
                    )
                }
            }
        }
    }

    // MARK: Internal

    /// Paints the pushed branches' rows in every listing of the
    /// repository; the numbers of the rows painted, for the
    /// enriched summaries beside them.
    static func paintListings(of pushed: Set<String>, repositoryPath: String, in metadata: inout AppMetadata)
        -> Set<Int>
    {
        var numbers = Set<Int>()
        let prefix = "list#" + repositoryPath + "#"
        for (key, listing) in metadata.pullRequestListsCache where key.hasPrefix(prefix) {
            var rewritten = listing
            rewritten.summaries = listing.summaries.map { row in
                guard pushed.contains(row.headBranch), row.state == "OPEN" else {
                    return row
                }

                numbers.insert(row.number)
                return row.awaitingChecks()
            }
            metadata.pullRequestListsCache[key] = rewritten
        }
        return numbers
    }

    /// A fetched summary as the caches take it: painted pending
    /// while its branch's mark stands and GitHub still reports the
    /// head it reported before the push, and as fetched once GitHub
    /// reports another, which ends the mark. A mark older than
    /// `pendingPatience` ends too, for a push GitHub never reflects
    /// in this pull request at all.
    static func painted(_ summary: PullRequestSummary, repositoryPath: String, in metadata: inout AppMetadata)
        -> PullRequestSummary
    {
        let key = Self.branchKey(repositoryPath: repositoryPath, branch: summary.headBranch)
        guard let old = metadata.pendingChecks[key] else {
            return summary
        }

        let since = metadata.fetchedAt[Self.pendingKey(key)] ?? .distantPast
        let caughtUp = summary.headCommit.map { $0 != old } ?? false
        if caughtUp || Date().timeIntervalSince(since) > Self.pendingPatience {
            metadata.pendingChecks.removeValue(forKey: key)
            metadata.fetchedAt.removeValue(forKey: Self.pendingKey(key))
            return summary
        }

        return summary.state == "OPEN" ? summary.awaitingChecks() : summary
    }

    /// The same for a listing.
    static func painted(
        _ summaries: [PullRequestSummary],
        repositoryPath: String,
        in metadata: inout AppMetadata,
    ) -> [PullRequestSummary] {
        summaries.map { painted($0, repositoryPath: repositoryPath, in: &metadata) }
    }

    /// How long a push is believed to be ahead of GitHub.
    static let pendingPatience: TimeInterval = 900

    /// Where a mark's own time is stamped, beside the fetch stamps.
    static func pendingKey(_ branchKey: String) -> String {
        "pending#" + branchKey
    }
}
