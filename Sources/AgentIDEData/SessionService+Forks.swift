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
        switch forkRemotes.answer(worktreePath: worktreePath, branch: branch) {
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

        // The fork's owner names its remote, as the viewer's own fork
        // is named after the viewer. A name already taken by another
        // URL keeps its own, and the push goes to the URL instead,
        // which works without a tracking ref to count against.
        let taken = await git.remoteURL(named: owner, worktreePath: worktreePath)
        guard taken == nil || taken == configured else {
            return (owner, configured)
        }

        do {
            try await git.adoptRemote(
                named: owner,
                url: configured,
                branch: branch,
                worktreePath: worktreePath,
            )
        } catch {
            // Offline, or a fork that has since gone: the URL is
            // still where this branch belongs.
            return (owner, configured)
        }

        return (owner, owner)
    }
}
