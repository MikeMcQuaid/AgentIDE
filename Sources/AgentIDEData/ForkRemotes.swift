import Synchronization

// MARK: - ForkAnswer

/// What is known about where a branch pushes: nothing yet, that it
/// pushes to origin like most branches, or the fork it belongs to.
/// A plain optional would have said this in two layers, and one of
/// them reads as "no answer" whichever way it is written.
enum ForkAnswer: Equatable {
    case unasked
    case origin
    case fork(owner: String, remote: String)
}

// MARK: - ForkRemotes

/// Which fork each checked-out pull request belongs to, worked out
/// once per branch and held for the rest of the run.
///
/// Answering costs two config reads and, the first time, a fetch:
/// cheap once, wasteful on every refresh of a tab that asks who a
/// branch pushes to before it draws. A branch that pushes to origin
/// is remembered too, since that is the common answer and the one
/// most worth not asking twice.
final class ForkRemotes: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the held answers; the rule wants the
        // release made explicit.
    }

    // MARK: Internal

    /// What was worked out for a branch, `unasked` until something
    /// has been.
    func answer(worktreePath: String, branch: String) -> ForkAnswer {
        held.withLock { $0[Self.key(worktreePath, branch)] ?? .unasked }
    }

    /// Records an answer, a branch that pushes to origin included.
    func remember(_ answer: ForkAnswer, worktreePath: String, branch: String) {
        held.withLock { $0[Self.key(worktreePath, branch)] = answer }
    }

    // MARK: Private

    private let held: Mutex<[String: ForkAnswer]> = .init([:])

    private static func key(_ worktreePath: String, _ branch: String) -> String {
        worktreePath + "\t" + branch
    }
}
