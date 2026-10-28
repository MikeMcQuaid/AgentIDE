/// Where a local branch is checked out and what it was cut from,
/// which tell a stack's own branches from neighbours. Split from the
/// branches for length.
public extension GitClient {
    /// The worktree path holding each checked-out local branch.
    func branchHolders(worktreePath: String) async -> [String: String] {
        let result = try? await git(
            ["for-each-ref", "--format=%(refname:short)%09%(worktreepath)", "refs/heads"],
            in: worktreePath,
            allowFailure: true,
        )
        var holders = [String: String]()
        for line in (result?.standardOutput ?? "").split(separator: "\n") {
            // A branch no worktree holds has an empty path, so one field.
            let fields = line.split(separator: "\t", maxSplits: 1)
            if let branch = fields.first, let path = fields.dropFirst().first {
                holders[String(branch)] = String(path)
            }
        }
        return holders
    }

    /// The local branch `branch` was created from, as its reflog's
    /// first entry records it, or nil when it was cut from `HEAD`
    /// or the reflog no longer reaches back that far.
    func createdFrom(_ branch: String, worktreePath: String) async -> String? {
        let result = try? await git(
            ["reflog", "show", "--format=%gs", "refs/heads/" + branch, "--"],
            in: worktreePath,
            allowFailure: true,
        )
        let prefix = "branch: Created from refs/heads/"
        guard let first = (result?.standardOutput ?? "").split(separator: "\n").last, first.hasPrefix(prefix) else {
            return nil
        }

        return String(first.dropFirst(prefix.count))
    }
}
