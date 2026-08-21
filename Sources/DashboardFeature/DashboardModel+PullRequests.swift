import AgentIDEData
import AgentIDEDomain
import Foundation
import TerminalUI

/// GitHub pull request polling, tiered by attention: the selected
/// worktree refreshes far more often than its repository's other
/// worktrees, which refresh more often than other expanded
/// repositories; repositories collapsed in the sidebar poll rarely.
/// GitHub rate limits, and attention rarely spans everything.
extension DashboardModel {
    /// The pull request a worktree's branch is showing, when the
    /// last fetch found one.
    public func pullRequest(for item: WorktreeItem) -> PullRequestSummary? {
        // flatMap flattens the dictionary's double optional.
        let cached = branchPullRequests[item.worktree.repositoryPath + "#" + item.worktree.branch]
            .flatMap(\.self)
        // Through the same choice the fetch makes, so a cache
        // holding a long-finished pull request stops speaking for
        // the branch the moment it is read, not at the next poll.
        let summary = cached.flatMap { Self.displayed([$0]) }
        return summary.map { stamped($0, repositoryPath: item.worktree.repositoryPath) }
    }

    /// Asks about one repository now, however recently the poll last
    /// asked: the manual answer to state GitHub changed between
    /// ticks, and to an outage that dropped a round of answers. One
    /// repository rather than all of them, since asking about every
    /// branch everywhere is how a rate limit is reached.
    public func refreshRepository(path: String) async {
        nextPullRequestFetch = nextPullRequestFetch.filter { $0.key.hasPrefix(path + "#") == false }
        queuesFetchedAt.removeValue(forKey: path)
        await refresh(forcing: path)
    }

    /// Refreshes which pull requests are in each repository's merge
    /// queue. One query per repository names every entry, which no
    /// per-pull-request field can answer, and it runs on the poll
    /// rather than per row.
    func refreshMergeQueues() async {
        for repository in groups.map(\.repository) where queuesDue(repository.path) {
            queuedNumbers[repository.path] = await github.queuedNumbers(repositoryPath: repository.path)
            queuesFetchedAt[repository.path] = Date()
        }
    }

    /// Whether a repository's queue is due another look: it changes
    /// as pull requests merge, so it is asked for regularly, but far
    /// less often than the branches themselves.
    private func queuesDue(_ repositoryPath: String) -> Bool {
        guard let fetched = queuesFetchedAt[repositoryPath] else {
            return true
        }

        return Date().timeIntervalSince(fetched) >= Self.queueInterval
    }

    /// The summary as the sidebar shows it: queued from the
    /// repository's own queue, and its unresolved conversations
    /// counted from the cache the conversation pane fills. GitHub only counts
    /// them through GraphQL, which the listing query cannot ask for
    /// and which is far too expensive to ask per branch per poll, so
    /// the row shows what the app has already read rather than
    /// fetching to find out.
    private func stamped(_ summary: PullRequestSummary, repositoryPath: String) -> PullRequestSummary {
        let key = AppMetadata.threadsKey(repositoryPath: repositoryPath, number: summary.number)
        let threads = store.load().threadsCache[key]?.threads ?? []
        let unresolved = threads.count { $0.isResolved == false }
        let queued = queuedNumbers[repositoryPath]?.contains(summary.number) ?? false
        // Copied rather than rebuilt field by field: a rebuild
        // silently drops whatever field it forgets, as it did with
        // the date a pull request closed.
        var stamped = summary
        stamped.unresolvedComments = unresolved
        stamped.isQueued = queued
        return stamped
    }

    /// One narrow query per due worktree branch instead of whole
    /// repositories: 200-row list queries timed out GitHub's GraphQL
    /// gateway on very large repositories. Failures keep the last
    /// cached answer, and a branch whose cached result is green and
    /// approved for its current commit is final and never refetched.
    func refreshStalePullRequests(forcing repositoryPath: String? = nil) async {
        hydratePullRequestCache()
        await refreshMergeQueues()
        let collapsed = Set(
            (UserDefaults.standard.string(forKey: "collapsedRepositories") ?? "")
                .split(separator: "\n")
                .map(String.init),
        )
        for group in groups {
            // An outage answers every branch identically, so one
            // branch probes for a recovery and the rest wait; the
            // repository a refresh was asked for keeps asking.
            let ridesOutOutage = ServiceStatus.shared.isUnavailable && repositoryPath != group.repository.path
            // The repository's own checkout is asked about too when
            // it is off its default branch: work done there has a
            // pull request like any other, and skipping the row left
            // it blank however often the poll came round.
            let rows = group.items.filter { $0.worktree.path != group.repository.path || isOffDefaultBranch($0) }
            for item in rows {
                let key = item.worktree.repositoryPath + "#" + item.worktree.branch
                if let due = nextPullRequestFetch[key], due > Date() {
                    continue
                }
                if ridesOutOutage, item.id != selection?.id {
                    continue
                }

                nextPullRequestFetch[key] = Date().addingTimeInterval(interval(for: item, collapsed: collapsed))
                do {
                    let summaries = try await github.pullRequests(
                        repositoryPath: group.repository.path,
                        scope: .branch(item.worktree.branch),
                    )
                    let summary = Self.displayed(summaries)
                    let previous = branchPullRequests[key].flatMap(\.self)
                    branchPullRequests[key] = summary
                    persist(summary, key: key)
                    await cleanUpIfMerged(item, previous: previous, fresh: summaries)
                    ServiceStatus.shared.recordSuccess()
                } catch {
                    ServiceStatus.shared.record(
                        failure: error,
                        doing: "Pull requests for " + group.repository.name,
                    )
                }
            }
        }
    }

    /// How many pull requests stack under this branch's, following
    /// base branches that are other cached pull requests' heads.
    /// 1 means unstacked.
    public func stackDepth(for item: WorktreeItem) -> Int {
        let prefix = item.worktree.repositoryPath + "#"
        var byHead = [String: PullRequestSummary]()
        let cached = branchPullRequests.filter { $0.key.hasPrefix(prefix) }.values.compactMap(\.self)
        // Stacking is a question about open pull requests; a merged
        // one's base is history.
        for summary in cached where summary.state == "OPEN" {
            byHead[summary.headBranch] = summary
        }
        guard var current = byHead[item.worktree.branch] else {
            return 1
        }

        var depth = 1
        var seen = Set([current.headBranch])
        while let next = byHead[current.baseBranch], seen.insert(next.headBranch).inserted {
            depth += 1
            current = next
        }
        return depth
    }

    // MARK: Private

    private static let selectedInterval: TimeInterval = 30
    private static let queueInterval: TimeInterval = 60

    /// How long after merging or closing a pull request still speaks
    /// for a branch of the same name: thirty days.
    private static let collisionAge: TimeInterval = 2_592_000

    /// A merge made on GitHub or elsewhere is tidied on the poll that
    /// first sees it: the branch's pull request that was open at the
    /// last poll now reports merged. Only that observed transition
    /// counts, never a merely missing pull request (a stale cache or
    /// a branch that never had one), and dirty worktrees are left
    /// alone by the cleanup itself.
    private func cleanUpIfMerged(
        _ item: WorktreeItem,
        previous: PullRequestSummary?,
        fresh: [PullRequestSummary],
    ) async {
        guard Self.observedMerge(previous: previous, fresh: fresh),
              deletingPaths.contains(item.worktree.path) == false,
              // Never pull the ground from under the worktree being
              // looked at: it would vanish mid-action and read as a
              // crash. Its context menu still offers the cleanup.
              selection?.worktree.path != item.worktree.path
        else {
            return
        }

        // The poll never prompts and never forces: a worktree the
        // merge-safe path refuses stays, with a note saying why, for
        // the user to clean up or delete by hand.
        switch await cleanUp(item: item) {
        case .dirty:
            ErrorLog.shared.report(
                "\(item.worktree.branch) merged but has uncommitted changes; left in place for you to review",
            )

        case .unmerged:
            ErrorLog.shared.report(
                "\(item.worktree.branch) merged but has commits not on the base branch; left in place",
            )

        case nil:
            break
        }
    }

    /// What a branch shows: its open pull request, or failing that
    /// its most recent recently-finished one, so a branch whose pull
    /// request merged reads as merged rather than as never having
    /// had one. Branch names get reused, and a pull request that
    /// finished long ago is a name collision rather than this
    /// branch's work, so it is ignored. Pure so the choice tests
    /// without GitHub.
    static func displayed(_ summaries: [PullRequestSummary], now: Date = Date()) -> PullRequestSummary? {
        if let open = summaries.first(where: { $0.state == "OPEN" }) {
            return open
        }

        let recent = summaries.filter { summary in
            guard let closed = summary.closedAt else {
                return false
            }

            return now.timeIntervalSince(closed) < Self.collisionAge
        }
        return recent.max { $0.number < $1.number }
    }

    /// Whether a poll observed the branch's pull request go from
    /// open to merged: the same number, open before, merged now. Pure
    /// so the rule tests without GitHub.
    static func observedMerge(previous: PullRequestSummary?, fresh: [PullRequestSummary]) -> Bool {
        guard let previous, previous.state == "OPEN" else {
            return false
        }

        return fresh.contains { $0.number == previous.number && $0.state == "MERGED" }
    }

    private static let selectedRepositoryInterval: TimeInterval = 120
    private static let expandedInterval: TimeInterval = 300
    private static let collapsedInterval: TimeInterval = 1_800

    /// Loads the persisted cache once, so badges paint on launch
    /// without waiting for the first fetch.
    private func hydratePullRequestCache() {
        guard branchPullRequests.isEmpty else {
            return
        }

        for (key, summary) in store.load().pullRequestCache {
            branchPullRequests[key] = summary
        }
    }

    private func persist(_ summary: PullRequestSummary?, key: String) {
        var metadata = store.load()
        if let summary {
            metadata.pullRequestCache[key] = summary
        } else {
            metadata.pullRequestCache.removeValue(forKey: key)
        }
        store.save(metadata)
    }

    private func interval(for item: WorktreeItem, collapsed: Set<String>) -> TimeInterval {
        if collapsed.contains(item.worktree.repositoryPath) {
            return Self.collapsedInterval
        }
        if selection?.id == item.id {
            return Self.selectedInterval
        }
        if selection?.worktree.repositoryPath == item.worktree.repositoryPath {
            return Self.selectedRepositoryInterval
        }
        return Self.expandedInterval
    }
}
