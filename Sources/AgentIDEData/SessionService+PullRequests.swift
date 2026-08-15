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
}
