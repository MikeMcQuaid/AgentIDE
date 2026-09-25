import AgentIDEDomain

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

    /// The GitHub owner the branch pushes to, which a pull request
    /// from a fork names as its head; nil when the branch has no
    /// remote or it is not on GitHub. Remembered against the config
    /// file the branch's remote lives in: three processes per branch
    /// per poll read the same answer all day.
    func headOwner(repositoryPath: String, branch: String) async -> String? {
        let modified = Self.configModified(at: repositoryPath)
        let key = repositoryPath + "#" + branch
        if let known = await RepositoryFacts.shared.headOwner(of: key, at: modified) {
            return known.value
        }

        let remote = await branchRemote(worktreePath: repositoryPath, branch: branch) ?? "origin"
        let owner: String? =
            if GitHubRemote.isURL(remote) {
                GitHubRemote.owner(ofURL: remote)
            } else {
                await remoteURL(named: remote, worktreePath: repositoryPath).flatMap(GitHubRemote.owner(ofURL:))
            }
        await RepositoryFacts.shared.remember(headOwner: owner, of: key, at: modified)
        return owner
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
        try await withRemoteOperation(worktreePath: worktreePath) {
            if await remoteURL(named: name, worktreePath: worktreePath) == nil {
                try await git(["remote", "add", name, url], in: worktreePath)
                try await git(["config", "--local", "remote." + name + ".agentide-created-url", url], in: worktreePath)
            }

            try await git(["fetch", "--quiet", name, branch], in: worktreePath)
            try await git(
                ["branch", "--set-upstream-to", name + "/" + branch, branch],
                in: worktreePath,
            )
            try await git(["config", "branch." + branch + ".pushremote", name], in: worktreePath)
        }
    }

    /// Removes only remotes this app added, after their branches are
    /// gone. Git config keeps ownership across app restarts.
    internal func removeUnusedForkRemotes(repositoryPath: String) async throws {
        try await withRemoteOperation(worktreePath: repositoryPath) {
            try await pruneForkRemotes(repositoryPath: repositoryPath)
        }
    }

    // MARK: Private

    private func pruneForkRemotes(repositoryPath: String) async throws {
        let added = try await git(
            ["config", "--local", "--null", "--get-regexp", #"^remote\..*\.agentide-created-url$"#],
            in: repositoryPath,
            allowFailure: true,
        )
        guard added.succeeded else {
            return
        }

        let references = try await git(
            ["config", "--null", "--get-regexp", #"^(branch\..*\.(remote|pushremote)|remote\.pushdefault)$"#],
            in: repositoryPath,
            allowFailure: true,
        )
        // No matching keys is exit 1; an unreadable config must
        // never be mistaken for proof that nothing uses a remote.
        guard references.succeeded || references.status == 1 else {
            return
        }

        // Read raw config before URL rewrites, including extra
        // values and options which mark a remote as customised.
        let configuration = try await git(
            ["config", "--null", "--get-regexp", #"^remote\."#], in: repositoryPath, allowFailure: true,
        )
        guard configuration.succeeded else {
            return
        }

        let used = Set(references.standardOutput.split(separator: "\0").compactMap { entry in
            entry.split(separator: "\n", maxSplits: 1).last.map(String.init)
        })
        for entry in added.standardOutput.split(separator: "\0") {
            let parts = entry.split(separator: "\n", maxSplits: 1)
            guard let key = parts.first, let url = parts.dropFirst().first.map(String.init) else {
                continue
            }

            let name = String(key.dropFirst("remote.".count).dropLast(".agentide-created-url".count))
            guard name != "origin", used.contains(name) == false, used.contains(url) == false else {
                continue
            }

            let prefix = "remote." + name + "."
            let expected = [
                prefix + "url\n" + url,
                prefix + "fetch\n+refs/heads/*:refs/remotes/" + name + "/*",
                prefix + "agentide-created-url\n" + url,
            ]
            guard configuration.standardOutput
                .split(separator: "\0")
                .filter({ $0.hasPrefix(prefix) })
                .map(String.init)
                .sorted() == expected.sorted()
            else {
                continue
            }

            try await git(["remote", "remove", name], in: repositoryPath)
        }
    }
}
