import AgentIDEDomain
import Foundation
import TerminalUI

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
                    let previous = branchPullRequests[key].flatMap(\.self)
                    branchPullRequests[key] = summary
                    persist(summary, key: key)
                    await cleanUpIfMerged(item, previous: previous, fresh: summaries)
                } catch {
                    ErrorLog.shared.report("Pull requests for \(group.repository.name): " + error.localizedDescription)
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
