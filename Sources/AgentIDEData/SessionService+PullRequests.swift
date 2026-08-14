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
}
