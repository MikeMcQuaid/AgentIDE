import Foundation
import Synchronization

/// The pane listing herdr last answered with, held so a reading that
/// failed is never shown as nothing running.
///
/// A failed listing says nothing at all about what is running, but
/// taken as an empty one it emptied every session in the app at
/// once: every row lost its agent, every pane read as exited and
/// only relaunching the app brought them back, though herdr had lost
/// nothing and the agents were still working. The hold is bounded,
/// so a herdr that really has gone is not painted as running for
/// ever: once the failures have lasted longer than `patience`, the
/// empty answer is believed.
final class LastPanes: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the held listing; the rule wants the
        // release made explicit.
    }

    // MARK: Internal

    /// Records what herdr answered, empty answers included: nothing
    /// running is a fact when the reading itself succeeded.
    func remember(_ panes: [HerdrPane], at moment: Date = Date()) {
        held.withLock { $0 = Held(panes: panes, answeredAt: moment) }
    }

    /// What to show for a reading that failed: the last answer while
    /// it is young enough to still describe the system, nothing once
    /// the failures have outlasted our patience.
    func kept(now: Date = Date()) -> [HerdrPane] {
        held.withLock { held in
            guard now.timeIntervalSince(held.answeredAt) < Self.patience else {
                return []
            }

            return held.panes
        }
    }

    // MARK: Private

    private struct Held {
        let panes: [HerdrPane]
        let answeredAt: Date
    }

    /// How long a failing herdr keeps the sessions it last named.
    /// Long enough to ride out a cull of the sandbox user or a
    /// server restart, short enough that a real shutdown shows.
    private static let patience: TimeInterval = 120

    private let held: Mutex<Held> = .init(Held(panes: [], answeredAt: .distantPast))
}
