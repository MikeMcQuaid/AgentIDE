import AgentIDEData
import TerminalUI

/// Reloading the listing and the merge queue answer, split from the
/// model body for length; the merge queue, loading and page-limit
/// flags are settable here for that reason.
extension PullRequestsModel {
    /// The merge queue answer for the repository, which decides
    /// whether the merge action queues or merges.
    func loadMergeQueue() async {
        hasMergeQueue = await fetchHasMergeQueue()
    }

    /// The cached listing paints instantly while the fetch runs; a
    /// kept selection is re-selected once the fetch answers, and a
    /// single result opens its conversation directly. Extending
    /// keeps the current page and raises the fetch limit.
    /// `refreshingFacts` re-reads what the worktree itself says:
    /// its signing, its rebase need, its template and its stack.
    /// Moving up and down a stack leaves all of that alone, since
    /// every entry shares one worktree, and asking git again is
    /// what made the move feel like a load rather than a click.
    func reload(keepingSelection: Bool = false, refreshingFacts: Bool = true) async {
        let previous = keepingSelection ? selected?.number : nil
        isLoading = true
        // The cache paints before any of the reading: the listing
        // this branch had last time is on screen at once, and the
        // fetch replaces it in place.
        page = 0
        if keepingSelection == false {
            selected = nil
        }
        paintCachedListing()
        // Selected from the cache, not after the fetch: a branch
        // with one pull request opens it the moment the tab does,
        // and clicking between worktrees paints what each had.
        if selected == nil, summaries.count == 1, let only = summaries.first {
            select(only)
        }
        loadDraft()
        if let worktree = branchItem?.worktree {
            if refreshingFacts {
                await refreshWorktreeFacts(worktree)
            } else {
                // An entry switch keeps the worktree's facts but
                // fills the form from this entry's own commits.
                await prefillFromSingleCommit(worktree)
            }
            // The count belongs to the entry, not to the worktree,
            // so an entry switch reads it again.
            commitsAboveBase = await fetchCommitCount(listedWorktree ?? worktree, listedRange)
        }
        defer {
            isLoading = false
            hasLoaded = true
        }
        // Captured before the await: a slow answer for an already
        // switched scope must neither show nor cache under the new
        // scope's key.
        let requested = cacheKey
        do {
            let limit = GitHubClient.listLimit
            let fetched = try await listing(limit: limit)
            guard Task.isCancelled == false, requested == cacheKey else {
                return
            }

            summaries = Self.worthShowing(fetched)
            fetchedLimit = limit
            pullRequests.rememberListing(
                repositoryPath: repository.path,
                scope: scope.listScope(branch: listedBranch),
                summaries: fetched,
            )
            // A branch with one live pull request opens it: there
            // is nothing else the list could be for.
            let chosen = summaries.first { $0.number == previous }
                ?? (summaries.count == 1 ? summaries.first : nil)
            if let chosen {
                select(chosen)
            }
            ServiceStatus.shared.recordSuccess()
            prefetchStack()
        } catch {
            ServiceStatus.shared.record(failure: error, doing: "Pull requests for " + repository.name)
        }
    }
}
