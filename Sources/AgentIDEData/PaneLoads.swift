import AgentIDEDomain
import Foundation
import Synchronization

// MARK: - PaneLoads

/// What each pane's process tree costs, remembered between readings.
///
/// Two things have to survive a reading: the shell process a pane
/// runs, which never changes for the life of the pane and costs a
/// herdr call to ask for, and when a pane's busy spell began, which
/// is the whole difference between a build finishing and a linter
/// spinning for half an hour.
final class PaneLoads: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the two dictionaries.
    }

    // MARK: Internal

    /// The shell process of a pane, if it has been asked for.
    func shell(of paneID: String) -> Int? {
        held.withLock { $0.shells[paneID] }
    }

    func remember(shell: Int, of paneID: String) {
        held.withLock { $0.shells[paneID] = shell }
    }

    /// Records a reading and answers what to show for it: nothing
    /// while the tree is quiet, and how long it has been busy once
    /// it is not.
    func reading(
        percent: Double,
        busiest: String,
        of worktreePath: String,
        now: Date = Date(),
    ) -> PaneLoad? {
        held.withLock { held in
            let since = PaneLoad.busySince(held.busySince[worktreePath], percent: percent, now: now)
            held.busySince[worktreePath] = since
            guard let since else {
                return nil
            }

            return PaneLoad(percent: percent, busiest: busiest, since: since)
        }
    }

    /// Forgets panes that are no longer listed, so a worktree that
    /// comes back is not judged by what it was doing before.
    func forgetAll(except worktreePaths: Set<String>) {
        held.withLock { held in
            held.busySince = held.busySince.filter { worktreePaths.contains($0.key) }
        }
    }

    // MARK: Private

    private struct Held {
        var shells: [String: Int] = [:]
        var busySince: [String: Date] = [:]
    }

    private let held: Mutex<Held> = .init(Held())
}
