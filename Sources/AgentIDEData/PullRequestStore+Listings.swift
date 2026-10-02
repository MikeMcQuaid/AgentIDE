import AgentIDEDomain
import Foundation

extension PullRequestStore {
    /// Keeps a fetched listing as its key's answer, painted and
    /// stamped now, corrects the enriched summaries it outdates and
    /// hands it back as the caches took it. Every listing lands
    /// here, whichever side fetched it.
    static func record(
        _ fetched: [PullRequestSummary],
        key: String,
        repositoryPath: String,
        in metadata: inout AppMetadata,
    ) -> [PullRequestSummary] {
        let kept = painted(fetched, repositoryPath: repositoryPath, in: &metadata)
        metadata.pullRequestListsCache[key] = CachedPullRequestList(summaries: kept)
        metadata.fetchedAt[key] = Date()
        correctSummaries(from: kept, repositoryPath: repositoryPath, in: &metadata)
        return kept
    }

    /// The row and the pane paint the enriched summary over the
    /// listing, and only open pull requests are enriched, so a
    /// listing is what notices one change state. One it reports
    /// merged or closed replaces a summary still calling it open;
    /// one it reports open again drops a finished summary's stamp,
    /// so the next enrichment asks rather than repeating the cache.
    static func correctSummaries(
        from listed: [PullRequestSummary],
        repositoryPath: String,
        in metadata: inout AppMetadata,
    ) {
        for summary in listed {
            let key = summaryKey(repositoryPath: repositoryPath, number: summary.number)
            guard let cached = metadata.enrichedSummaryCache[key]?.summary else {
                continue
            }

            if summary.state == "OPEN" {
                if cached.state != "OPEN" {
                    metadata.fetchedAt.removeValue(forKey: key)
                }
            } else if cached.state == "OPEN" {
                metadata.enrichedSummaryCache[key] = CachedSummary(summary: summary)
                metadata.pendingSince.removeValue(forKey: key)
            }
        }
    }
}
