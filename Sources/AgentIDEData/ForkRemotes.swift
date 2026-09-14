import Foundation
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
/// once per branch until the repository's config changes.
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
    func answer(worktreePath: String, branch: String, modified: Date? = nil) -> ForkAnswer {
        held.withLock { entries in
            guard let entry = entries[Self.key(worktreePath, branch)], entry.modified == modified else {
                return .unasked
            }

            return entry.answer
        }
    }

    /// Records an answer, a branch that pushes to origin included.
    func remember(_ answer: ForkAnswer, worktreePath: String, branch: String, modified: Date? = nil) {
        held.withLock { $0[Self.key(worktreePath, branch)] = (answer, modified) }
    }

    // MARK: Private

    private let held: Mutex<[String: (answer: ForkAnswer, modified: Date?)]> = .init([:])

    private static func key(_ worktreePath: String, _ branch: String) -> String {
        worktreePath + "\t" + branch
    }
}
