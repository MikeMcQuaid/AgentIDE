import AgentIDEDomain

/// Pull requests opened from a fork. `gh pr checkout` writes the
/// fork's URL into the branch's config and names no remote for it,
/// which leaves the branch with no tracking ref: the sidebar could
/// count nothing, the pull request's own state was read against the
/// wrong repository and a push aimed at origin would have opened a
/// branch in the repository the pull request is against.
public extension SessionService {
    /// The fork a branch belongs to, naming a remote for it the
    /// first time and tracking the branch there. Nil when the branch
    /// belongs to origin, which is every branch of your own.
    func forkRemote(worktreePath: String, branch: String) async -> (owner: String, remote: String)? {
        switch forkRemotes.answer(
            worktreePath: worktreePath,
            branch: branch,
            modified: GitClient.configModified(at: worktreePath),
        ) {
        case .origin:
            return nil

        case let .fork(owner, remote):
            return (owner, remote)

        case .unasked:
            let found = await readForkRemote(worktreePath: worktreePath, branch: branch)
            forkRemotes.remember(
                found.map { ForkAnswer.fork(owner: $0.owner, remote: $0.remote) } ?? .origin,
                worktreePath: worktreePath,
                branch: branch,
                modified: GitClient.configModified(at: worktreePath),
            )
            return found
        }
    }

    // MARK: Internal

    /// Works the answer out from git's own config, adopting the URL
    /// `gh` left behind as a named remote when it finds one.
    internal func readForkRemote(worktreePath: String, branch: String) async -> (owner: String, remote: String)? {
        guard let configured = await git.branchRemote(worktreePath: worktreePath, branch: branch),
              configured != "origin"
        else {
            return nil
        }
        guard GitHubRemote.isURL(configured) else {
            // Already a remote of its own, whatever it is called.
            let url = await git.remoteURL(named: configured, worktreePath: worktreePath)
            return (url.flatMap(GitHubRemote.owner(ofURL:)) ?? configured, configured)
        }
        guard let owner = GitHubRemote.owner(ofURL: configured) else {
            return nil
        }

        var name = owner
        var suffix = 2
        while let taken = await git.remoteURL(named: name, worktreePath: worktreePath), taken != configured {
            name = owner + "-" + String(suffix)
            suffix += 1
        }

        do {
            try await git.adoptRemote(
                named: name,
                url: configured,
                branch: branch,
                worktreePath: worktreePath,
            )
        } catch {
            // A failed fetch still leaves a named remote to retry.
            return await (
                owner,
                git.remoteURL(named: name, worktreePath: worktreePath) == configured ? name : configured,
            )
        }

        return (owner, name)
    }

    internal func remoteBranchRef(worktreePath: String, branch: String) async -> String {
        let remote = await forkRemote(worktreePath: worktreePath, branch: branch)?.remote ?? "origin"
        return "refs/remotes/" + remote + "/" + branch
    }

    internal func stackingBlocker(branches: [String], worktreePath: String) async -> String? {
        for branch in branches where await forkRemote(worktreePath: worktreePath, branch: branch) != nil {
            return "GitHub does not support pull request stacks across forks."
        }
        return nil
    }

    @discardableResult
    internal func requireStackable(_ stack: BranchStack) throws -> BranchStack {
        if let blocker = stack.stackingBlocker {
            throw SessionServiceError(blocker)
        }
        return stack
    }
}
