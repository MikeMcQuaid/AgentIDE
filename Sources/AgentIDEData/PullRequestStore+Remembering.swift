import AgentIDEDomain

/// Answers fetched elsewhere, remembered so they answer later reads
/// and hold off later fetches like the store's own. Split from the
/// store for length.
public extension PullRequestStore {
    /// Remembers a listing fetched elsewhere, so it answers later
    /// reads and holds off later fetches like the store's own, and
    /// hands it back as the caches took it: a pushed branch's row
    /// painted pending until GitHub has caught up.
    @discardableResult
    func rememberListing(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        summaries: [PullRequestSummary],
    ) -> [PullRequestSummary] {
        var kept = summaries
        store.update { metadata in
            kept = Self.record(
                summaries,
                key: Self.listingKey(repositoryPath: repositoryPath, scope: scope),
                repositoryPath: repositoryPath,
                in: &metadata,
            )
        }
        return kept
    }

    /// Records what a branch is showing; nil forgets it, which is
    /// what a branch whose pull request has gone gets.
    func rememberBranchSummary(
        _ summary: PullRequestSummary?,
        repositoryPath: String,
        branch: String,
    ) {
        let key = Self.branchKey(repositoryPath: repositoryPath, branch: branch)
        store.update { metadata in
            if let summary {
                metadata.pullRequestCache[key] = Self.painted(summary, repositoryPath: repositoryPath, in: &metadata)
                if summary.state != "OPEN" {
                    metadata.fetchedAt.removeValue(
                        forKey: Self.mergeRequestKey(repositoryPath: repositoryPath, branch: branch),
                    )
                }
            } else {
                metadata.pullRequestCache.removeValue(forKey: key)
            }
        }
    }

    /// Remembers a summary fetched elsewhere.
    func rememberSummary(repositoryPath: String, summary: PullRequestSummary) {
        store.update { metadata in
            metadata.enrichedSummaryCache[Self.summaryKey(repositoryPath: repositoryPath, number: summary.number)] =
                CachedSummary(summary: Self.painted(summary, repositoryPath: repositoryPath, in: &metadata))
        }
    }
}
