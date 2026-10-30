import SanductorDomain
import TerminalUI

/// What the tab is listing and how it asks for it. Split from the
/// model for length.
extension PullRequestsModel {
    /// Takes the cache's summary for the selected pull request and
    /// every listed row, so what the sidebar just learnt shows here
    /// too; the cache is written by whichever side fetched last.
    func repaintFromCache() {
        let listed = pullRequests.cachedListing(
            repositoryPath: repository.path,
            scope: scope.listScope(branch: listedBranch),
        ) ?? summaries
        summaries = Self.worthShowing(listed).map { row in
            withCachedUnresolved(pullRequests.cachedSummary(repositoryPath: repository.path, number: row.number) ?? row)
        }
        page = min(page, max(0, summaries.count - 1) / PullRequestListView.pageSize)
        if let selected {
            guard let listedSelection = summaries.first(where: { $0.number == selected.number }) else {
                self.selected = nil
                return
            }

            let cached = pullRequests.cachedSummary(repositoryPath: repository.path, number: selected.number)
                ?? listedSelection
            let painted = withCachedUnresolved(cached)
            if painted != selected {
                self.selected = painted
            }
        }
    }

    /// The branch the tab lists and compares against: the checked
    /// out one when known, the worktree's recorded one otherwise.
    var listedBranch: String? {
        stacking.selected ?? currentBranch ?? branch
    }

    /// What the listing on screen is of, so an answer that arrives
    /// after the tab has moved on is dropped rather than shown.
    var cacheKey: String {
        String(describing: scope) + "#" + (listedBranch ?? "")
    }

    /// The worktree listing, or nothing at all on the default
    /// branch: asking GitHub for a pull request whose head is
    /// `main` searches a repository's whole history of them to say
    /// what the branch itself already says, which on a large tap
    /// takes seconds every time the tab opens.
    func listing(limit: Int) async throws -> [PullRequestSummary] {
        guard scope != .worktree || listedBranch != defaultBranch else {
            return []
        }

        return try await fetchList(scope.listScope(branch: listedBranch), limit)
    }

    /// Fetches the listing up to `limit` and shows it; false when the
    /// tab moved to another scope or branch while it was asked, so
    /// the answer was dropped.
    func showListing(limit: Int) async throws -> Bool {
        // Captured before the await: a slow answer for an already
        // switched scope must neither show nor cache under the new
        // scope's key, and one a reload overtook must not replace
        // the reload's rows.
        let requested = cacheKey
        let generation = listingGeneration
        let fetched = try await listing(limit: limit)
        guard Task.isCancelled == false, requested == cacheKey, generation == listingGeneration else {
            return false
        }

        // As the caches took it: a pushed branch's row stays
        // pending until GitHub has caught up with the push.
        let kept = pullRequests.rememberListing(
            repositoryPath: repository.path,
            scope: scope.listScope(branch: listedBranch),
            summaries: fetched,
            limit: limit,
        )
        summaries = Self.worthShowing(kept)
        fetchedLimit = max(limit, kept.count)
        return true
    }

    /// Moves to the next page, asking GitHub for one more page first
    /// when the last answer filled its limit and holds nothing for
    /// it. An answer with nothing further steps back to the last
    /// page that has rows.
    func showNextPage() async {
        let generation = listingGeneration
        page += 1
        let pageSize = PullRequestListView.pageSize
        guard hasMore, summaries.count <= page * pageSize else {
            return
        }

        isLoading = true
        defer {
            if generation == listingGeneration {
                isLoading = false
                page = min(page, max(0, summaries.count - 1) / pageSize)
            }
        }
        do {
            _ = try await showListing(limit: (page + 1) * pageSize)
        } catch where generation == listingGeneration {
            ServiceStatus.shared.record(failure: error, doing: "Pull requests for " + repository.name)
        } catch {
            // A reload overtook this fetch and answers for it.
        }
    }
}
