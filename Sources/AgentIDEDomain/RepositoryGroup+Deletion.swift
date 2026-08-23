public extension RepositoryGroup {
    /// Why the repository's checkout cannot be deleted from disk,
    /// nil when it can: deleting is only offered once nothing would
    /// be lost, so the checkout must be alone (no worktrees), idle
    /// (no running agent), clean (nothing uncommitted or untracked)
    /// and level with origin's default branch as last fetched.
    var deletionBlocker: String? {
        let worktrees = items.filter { $0.worktree.path != repository.path }
        if worktrees.isEmpty == false {
            return String(worktrees.count)
                + (worktrees.count == 1 ? " worktree still exists" : " worktrees still exist")
        }
        if items.contains(where: { $0.session?.status == .running }) {
            return "an agent is still running"
        }
        guard let checkout = items.first(where: { $0.worktree.path == repository.path }) else {
            return "the checkout has not been read yet"
        }

        if checkout.isDirty {
            return "the checkout has uncommitted or untracked files"
        }
        guard let ahead = checkout.aheadOfDefault, let behind = checkout.behindDefault else {
            return "where the checkout stands against origin is unknown"
        }

        if ahead > 0 || behind > 0 {
            return "the checkout is " + String(ahead) + " ahead and " + String(behind)
                + " behind origin's default branch"
        }
        return nil
    }
}
