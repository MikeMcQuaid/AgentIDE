/// The remotes a branch belongs to. A pull request opened from a fork
/// is checked out with the fork's URL written straight into the
/// branch's config and no remote named for it, which leaves the
/// branch without a tracking ref: nothing could count what was
/// unpushed, and a push aimed at origin would have landed the
/// contributor's branch in the repository the pull request is
/// against.
public extension GitClient {
    /// Where a branch pushes, as git config has it: a remote's name,
    /// or a URL when that is what was written there. Nil when the
    /// branch has neither.
    func branchRemote(worktreePath: String, branch: String) async -> String? {
        for key in ["branch." + branch + ".pushremote", "branch." + branch + ".remote"] {
            let result = try? await git(["config", "--get", key], in: worktreePath, allowFailure: true)
            let value = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    /// A remote's URL, nil when there is no such remote.
    func remoteURL(named name: String, worktreePath: String) async -> String? {
        let result = try? await git(["remote", "get-url", name], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        let url = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    /// Adds a remote, fetches the one branch it is wanted for and
    /// points the branch at it, so counts, diffs and pushes all read
    /// the fork rather than the repository the pull request is
    /// against. A remote that is already there is left alone.
    func adoptRemote(named name: String, url: String, branch: String, worktreePath: String) async throws {
        if await remoteURL(named: name, worktreePath: worktreePath) == nil {
            try await git(["remote", "add", name, url], in: worktreePath)
        }

        try await git(["fetch", "--quiet", name, branch], in: worktreePath)
        try await git(
            ["branch", "--set-upstream-to", name + "/" + branch, branch],
            in: worktreePath,
        )
    }
}
