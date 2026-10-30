extension GitClient {
    /// Captures the lease before rebasing, so later background fetches cannot change it.
    func preparePush(worktreePath: String, branch: String, remote: String) async throws -> String {
        try await git(["fetch", "--prune", remote], in: worktreePath)
        guard let tip = await commitHash(of: "refs/remotes/" + remote + "/" + branch, worktreePath: worktreePath) else {
            return ""
        }
        guard await isAncestor(tip, of: branch, worktreePath: worktreePath) == false,
              await refWasBranchTip(worktreePath: worktreePath, branch: branch, ref: tip) == false
        else {
            return tip
        }

        try await rebaseForPush(worktreePath: worktreePath, branch: branch, onto: tip)
        return tip
    }

    /// Integrates in the branch's own worktree and restores whichever branch was selected.
    func rebaseForPush(
        worktreePath: String, branch: String, onto tip: String, from oldBase: String? = nil,
    ) async throws {
        let path = await branchHolders(worktreePath: worktreePath)[branch] ?? worktreePath
        let held = await currentBranch(worktreePath: path)
        guard let held, await isDirty(worktreePath: path) == false else {
            throw SessionServiceError("Commit or discard the worktree's changes before integrating remote work.")
        }

        do {
            if let oldBase {
                try await rebaseSigned(branch: branch, onto: tip, from: oldBase, worktreePath: path)
            } else {
                try await rebaseSigned(worktreePath: path, branch: branch, onto: tip)
            }
        } catch {
            if held != branch {
                try? await checkout(branch: held, worktreePath: path)
            }
            throw error
        }
        if held != branch {
            try await checkout(branch: held, worktreePath: path)
        }
    }
}
