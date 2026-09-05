import Synchronization

/// Which fork each checked-out pull request belongs to, worked out
/// once per branch and held for the rest of the run.
///
/// Answering costs two config reads and, the first time, a fetch:
/// cheap once, wasteful on every refresh of a tab that asks who a
/// branch pushes to before it draws.
final class ForkRemotes: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the held answers; the rule wants the
        // release made explicit.
    }

    // MARK: Internal

    /// The answer already worked out for a branch, or nil when none
    /// has been. The outer optional is whether it was asked, the
    /// inner one whether the branch has a fork of its own.
    func answer(worktreePath: String, branch: String) -> (owner: String, remote: String)?? {
        held.withLock { $0[Self.key(worktreePath, branch)] }
    }

    /// Records an answer, a branch that pushes to origin included.
    func remember(_ answer: (owner: String, remote: String)?, worktreePath: String, branch: String) {
        held.withLock { $0[Self.key(worktreePath, branch)] = answer }
    }

    /// Forgets a branch, for a worktree that has moved to another
    /// pull request.
    func forget(worktreePath: String, branch: String) {
        held.withLock { $0[Self.key(worktreePath, branch)] = nil }
    }

    // MARK: Private

    private let held: Mutex<[String: (owner: String, remote: String)?]> = .init([:])

    private static func key(_ worktreePath: String, _ branch: String) -> String {
        worktreePath + "\t" + branch
    }
}
