import Synchronization

/// A wake a watcher rings and a loop waits on, with a timeout, with
/// nothing cancelled on either side.
///
/// The spool loop used to race an `AsyncStream` iterator against a
/// sleep in a task group and cancel the loser. Cancelling a task
/// awaiting `AsyncStream.next()` finishes the stream: its
/// termination handler runs, the dispatch source behind it is
/// cancelled, and every later `next()` returns nil at once. From
/// the first idle timeout on, every wait came back immediately and
/// the loop scanned the spool directory flat out, which held the
/// app at a core and a half from eight seconds after launch. Here a
/// ring resumes the waiter or is kept for the next one, and a
/// timeout resumes only the waiter it was set for.
final class DirectoryWake: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the held waiter, which is never left
        // waiting: a timeout always resumes it.
    }

    // MARK: Internal

    /// Wakes the waiter, or keeps the ring for the next wait when
    /// nobody is waiting, so an event between two waits is never
    /// lost. Rings coalesce: one is as good as ten.
    func ring() {
        let waiter = held.withLock { held -> CheckedContinuation<Void, Never>? in
            guard let waiting = held.waiter else {
                held.pending = true
                return nil
            }

            held.waiter = nil
            held.generation += 1
            return waiting
        }
        waiter?.resume()
    }

    /// Returns on the next ring or after the timeout, whichever
    /// comes first; at once when a ring is already waiting.
    func wait(timeout: Duration) async {
        await withCheckedContinuation { continuation in
            // One lock take decides: a ring already waiting resumes
            // at once, otherwise the waiter is installed under the
            // same lock a ring would take. Checked and installed in
            // two takes, a ring between them was kept for the next
            // wait while this one slept its whole safety tick.
            let generation: Int? = held.withLock { held in
                if held.pending {
                    held.pending = false
                    return nil
                }

                held.waiter = continuation
                return held.generation
            }
            guard let generation else {
                continuation.resume()
                return
            }

            Task {
                try? await Task.sleep(for: timeout)
                self.expire(generation)
            }
        }
    }

    // MARK: Private

    private struct Held {
        var waiter: CheckedContinuation<Void, Never>?
        var pending = false
        /// Bumped whenever a waiter is resumed, so a timeout set for
        /// an earlier wait never resumes a later one.
        var generation = 0
    }

    private let held: Mutex<Held> = .init(Held())

    /// Resumes the waiter a timeout was set for, if it is still the
    /// one waiting.
    private func expire(_ generation: Int) {
        let waiter = held.withLock { held -> CheckedContinuation<Void, Never>? in
            guard held.generation == generation, let waiting = held.waiter else {
                return nil
            }

            held.waiter = nil
            held.generation += 1
            return waiting
        }
        waiter?.resume()
    }
}
