import AgentIDEDomain

/// Sessions on a pull request's own branch, checked out in a worktree
/// of their own.
public extension SessionService {
    /// Creates a session on a pull request's own branch: the worktree
    /// is checked out with `gh pr checkout`, so pushes and pulls
    /// track the pull request directly. A pull request already
    /// checked out is worked on where it is, and one with an agent
    /// running there answers with that session.
    func createSession(
        fromPullRequest number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        await clearQuarantine(for: agent)
        async let probed = probeVersion(of: agent)
        let detail = try await github.pullRequestDetail(repositoryPath: repository.path, number: number)
        let prompt = GitHubClient.pullRequestPrompt(
            number: number,
            title: detail.title,
            body: detail.body,
            context: context,
        )
        let branch = detail.headBranch.isEmpty ? "pr-\(number)" : detail.headBranch
        // One checkout at a time per repository, since `gh pr
        // checkout` writes the branch's config.
        let checkout = try await git.withRemoteOperation(worktreePath: repository.path, onWait: progress) {
            try await checkOut(pullRequest: number, branch: branch, repository: repository)
        }
        if checkout.isNew {
            // A pull request from a fork is checked out with the fork's
            // URL and no remote named for it: naming one here is what
            // gives the branch a tracking ref to count against and a
            // remote to push back to.
            _ = await forkRemote(worktreePath: checkout.worktree.path, branch: branch)
        } else if let running = await liveSessionName(worktreePath: checkout.worktree.path) {
            await progress("An agent is already running in `" + checkout.worktree.path + "`")
            return running
        } else {
            // A finished pane can still hold the name.
            await killSession(
                name: SessionName.make(repository: repository.name, branch: checkout.worktree.branch, agent: agent),
            )
        }
        let slot = WorktreeSlot(repository: repository, branch: checkout.worktree.branch, path: checkout.worktree.path)
        return try await start(
            prompt: prompt,
            agent: agent,
            options: options,
            slot: slot,
            probed: probed,
        )
    }

    /// The worktree a pull request's earlier launch checked out, found
    /// by its `pr-<number>` directory rather than its branch, which
    /// two forks' pull requests can share; otherwise a new one.
    private func checkOut(
        pullRequest number: Int,
        branch: String,
        repository: Repository,
    ) async throws -> (worktree: Worktree, isNew: Bool) {
        let name = "pr-\(number)"
        let path = worktreeContainer(repository: repository) + "/" + name
        if let existing = try await git.worktrees(of: repository).first(where: { $0.path == path }) {
            await progress("Pull request #\(number) is already checked out at `" + path + "`")
            return (existing, false)
        }

        let created = try await createDetachedWorktreePath(repository: repository, name: name)
        try await github.checkoutPullRequest(worktreePath: created, number: number)
        let worktree = Worktree(
            repositoryName: repository.name, repositoryPath: repository.path, branch: branch, path: created,
        )
        return (worktree, true)
    }
}
