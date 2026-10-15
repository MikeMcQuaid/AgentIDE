import AgentIDEDomain

/// Origin's branches and checking one out as a worktree of its own,
/// split from the branch file for length.
public extension GitClient {
    /// Origin's branches as last fetched, most recently committed
    /// first, leaving out `HEAD` and every branch a worktree holds,
    /// since git refuses to check out a branch twice.
    func remoteBranches(repositoryPath: String) async -> [String] {
        let held = try? await git(
            ["for-each-ref", "--format=%(if)%(worktreepath)%(then)%(refname:lstrip=2)%(end)", "refs/heads"],
            in: repositoryPath,
            allowFailure: true,
        )
        let remote = try? await git(
            ["for-each-ref", "--sort=-committerdate", "--format=%(refname:lstrip=3)", "refs/remotes/origin"],
            in: repositoryPath,
            allowFailure: true,
        )
        let heldNames = Set((held?.standardOutput ?? "").split(separator: "\n").map(String.init))
        return (remote?.standardOutput ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { $0 != "HEAD" && heldNames.contains($0) == false }
    }

    /// Adds a worktree at `path` on `branch` tracking origin's copy.
    /// A local branch of that name is used as it stands, and only
    /// fast-forwarded when origin's copy contains it, so no local
    /// commit is lost, then set to track origin's copy whatever it
    /// tracked before; otherwise the branch is created from origin's.
    func addRemoteBranchWorktree(repository: Repository, branch: String, at path: String) async throws {
        let remoteRef = "refs/remotes/origin/" + branch
        guard await branchExists(repository: repository, branch: branch) else {
            try await git(["worktree", "add", "--track", "-b", branch, path, remoteRef], in: repository.path)
            return
        }

        if await isAncestor("refs/heads/" + branch, of: remoteRef, worktreePath: repository.path) {
            try await git(["branch", "--force", branch, remoteRef], in: repository.path)
        }
        try await git(["branch", "--set-upstream-to=origin/" + branch, branch], in: repository.path)
        try await git(["worktree", "add", path, branch], in: repository.path)
    }
}
