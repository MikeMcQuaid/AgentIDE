import AgentIDEData
import AgentIDEDomain

/// What the tab is listing and how it asks for it. Split from the
/// model for length.
extension PullRequestsModel {
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
}
