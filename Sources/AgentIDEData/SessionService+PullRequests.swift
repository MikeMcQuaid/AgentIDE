import AgentIDEDomain

/// Pushing branches and inspecting pull
/// requests.
public extension SessionService {
    /// Pushes the branch to origin without opening anything. An
    /// unsigned tip refuses: every pushed commit must be GPG signed
    /// (a local hook enforces the same), and Rebase on origin is the
    /// signing path.
    func push(worktree: Worktree) async throws {
        guard await git.isCommitSigned(worktreePath: worktree.path) else {
            throw SessionServiceError(
                "The tip commit is not GPG signed; Rebase on origin signs the branch before pushing.",
            )
        }

        try await git.push(worktreePath: worktree.path, branch: worktree.branch)
    }

    /// Whether the worktree's tip commit is GPG signed, gating Push.
    func isTipSigned(worktreePath: String) async -> Bool {
        await git.isCommitSigned(worktreePath: worktreePath)
    }

    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable.
    func currentBranch(worktreePath: String) async -> String? {
        await git.currentBranch(worktreePath: worktreePath)
    }

    /// The branch's full commit messages beyond origin/HEAD, oldest
    /// first, for drafting pull request descriptions.
    func commitMessages(worktree: Worktree) async -> [String] {
        await git.commitMessages(worktreePath: worktree.path, baseRef: "origin/HEAD")
    }

    /// A pull request title and body drafted by the on-device model,
    /// nil when it is unavailable or unhelpful.
    func draftPullRequestDescription(fromCommits commits: [String]) async -> (title: String, body: String)? {
        await summariser.pullRequestDescription(fromCommits: commits)
    }

    /// The pull request template completed from the commits by the
    /// on-device model, nil when it is unavailable or unhelpful.
    func fillPullRequestTemplate(fromCommits commits: [String], template: String) async -> String? {
        await summariser.filledTemplate(fromCommits: commits, template: template)
    }

    /// After merging from the main checkout: return to the default
    /// branch, reset it to origin when it carries nothing of its
    /// own, and delete the merged branch with `-d` so an unmerged
    /// branch survives. Dirty checkouts and worktrees other than
    /// the main checkout are left untouched.
    func cleanUpAfterMerge(worktree: Worktree, mergedBranch: String) async {
        guard worktree.path == worktree.repositoryPath,
              await git.isDirty(worktreePath: worktree.path) == false
        else {
            return
        }

        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        try? await git.fetch(repositoryPath: worktree.path)
        guard let base = await git.defaultBaseRef(of: repository) else {
            return
        }

        // defaultBaseRef answers `origin/main` or a bare local name.
        let branch = base.hasPrefix("origin/") ? String(base.dropFirst("origin/".count)) : base
        guard branch != mergedBranch,
              await (try? git.checkout(worktreePath: worktree.path, branch: branch)) != nil
        else {
            return
        }

        let counts = await git.aheadBehind(worktreePath: worktree.path, baseRef: "origin/" + branch)
        if counts?.ahead == 0 {
            try? await git.resetHard(worktreePath: worktree.path, ref: "origin/" + branch)
        }
        await git.deleteMergedBranch(worktreePath: worktree.path, branch: mergedBranch)
    }
}
