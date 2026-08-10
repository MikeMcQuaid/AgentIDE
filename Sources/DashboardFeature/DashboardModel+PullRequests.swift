import AgentIDEDomain
import Foundation

/// GitHub pull request polling, tiered by attention: the selected
/// worktree refreshes far more often than its repository's other
/// worktrees, which refresh more often than other expanded
/// repositories; repositories collapsed in the sidebar poll rarely.
/// GitHub rate limits, and attention rarely spans everything.
extension DashboardModel {
    /// The open pull request for a worktree's branch, when the last
    /// fetch found one.
    public func pullRequest(for item: WorktreeItem) -> PullRequestSummary? {
        // flatMap flattens the dictionary's double optional.
        branchPullRequests[item.worktree.repositoryPath + "#" + item.worktree.branch].flatMap(\.self)
    }

    /// One narrow query per due worktree branch instead of whole
    /// repositories: 200-row list queries timed out GitHub's GraphQL
    /// gateway on very large repositories. Failures keep the last
    /// cached answer, and a branch whose cached result is green and
    /// approved for its current commit is final and never refetched.
    func refreshStalePullRequests() async {
        hydratePullRequestCache()
        let collapsed = Set(
            (UserDefaults.standard.string(forKey: "collapsedRepositories") ?? "")
                .split(separator: "\n")
                .map(String.init),
        )
        for group in groups {
            for item in group.items.dropFirst() {
                let key = item.worktree.repositoryPath + "#" + item.worktree.branch
                if let due = nextPullRequestFetch[key], due > Date() {
                    continue
                }
                if await isFinal(branchPullRequests[key].flatMap(\.self), for: item) {
                    continue
                }

                nextPullRequestFetch[key] = Date().addingTimeInterval(interval(for: item, collapsed: collapsed))
                do {
                    let summaries = try await github.pullRequests(
                        repositoryPath: group.repository.path,
                        scope: .branch(item.worktree.branch),
                    )
                    let summary = summaries.first { $0.state == "OPEN" }
                    branchPullRequests[key] = summary
                    persist(summary, key: key)
                } catch {
                    status = "Pull requests for \(group.repository.name): " + error.localizedDescription
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
        for case let (key, summary?) in branchPullRequests where key.hasPrefix(prefix) {
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

    /// Green checks and an approving review for the branch's current
    /// commit never regress, so that state needs no refetch.
    private func isFinal(_ cached: PullRequestSummary?, for item: WorktreeItem) async -> Bool {
        guard let cached,
              cached.state == "OPEN",
              cached.checks == "SUCCESS",
              cached.reviewDecision == "APPROVED",
              cached.headOID.isEmpty == false
        else {
            return false
        }

        let local = await service.headCommit(worktreePath: item.worktree.path)
        return local == cached.headOID
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
