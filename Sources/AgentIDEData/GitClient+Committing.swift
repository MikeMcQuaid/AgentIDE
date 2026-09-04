/// Making commits: everything, some named paths, or folded into
/// the commit before. Split from the client for length.
public extension GitClient {
    /// Stages everything and commits it.
    func commitAll(worktreePath: String, message: String) async throws {
        try await git(["add", "-A"], in: worktreePath)
        try await git(["commit", "-m", message], in: worktreePath)
    }

    /// Commits named paths and leaves the rest of the worktree
    /// alone. The paths are staged first, since a commit given a
    /// pathspec refuses a path git has never seen, and named again
    /// on the commit, so whatever else was staged stays staged: a
    /// selective commit must not sweep up what the agent left in
    /// the index.
    func commit(worktreePath: String, paths: [String], message: String) async throws {
        guard paths.isEmpty == false else {
            return
        }

        try await git(["add", "--"] + paths, in: worktreePath)
        try await git(["commit", "-m", message, "--"] + paths, in: worktreePath)
    }

    /// Amends the last commit, optionally replacing its message.
    func amend(worktreePath: String, message: String?) async throws {
        var arguments = ["commit", "--amend"]
        if let message {
            arguments += ["-m", message]
        } else {
            arguments.append("--no-edit")
        }
        try await git(arguments, in: worktreePath)
    }

    /// Folds named paths into the last commit, keeping everything
    /// else where it is. The paths are staged first, since a commit
    /// given a pathspec refuses a path git has never seen, and named
    /// again on the amend, which then takes the last commit's tree
    /// plus those paths' working-tree state: anything else already
    /// staged stays staged, and anything else uncommitted stays
    /// uncommitted.
    func amend(worktreePath: String, paths: [String], message: String?) async throws {
        guard paths.isEmpty == false else {
            try await git(["add", "-A"], in: worktreePath)
            try await amend(worktreePath: worktreePath, message: message)
            return
        }

        try await git(["add", "--"] + paths, in: worktreePath)
        let wording = message.map { ["-m", $0] } ?? ["--no-edit"]
        try await git(["commit", "--amend"] + wording + ["--"] + paths, in: worktreePath)
    }
}
