import Foundation
import Network
import Synchronization

/// Whether this machine has a route to the internet at all, from
/// the system's own path monitor rather than a poll of our own.
///
/// Every GitHub question goes out through `gh`, so a machine off the
/// network answers each one with the same failure: without this the
/// messages pane filled with one identical complaint per branch per
/// poll, and the app kept spawning processes that could not succeed.
public final class NetworkMonitor: Sendable {
    // MARK: Lifecycle

    /// Creates a monitor; nothing is watched until `changes` is
    /// consumed.
    public init() {
        // The path monitor is created per stream.
    }

    deinit {
        // The stream's termination cancels the path monitor.
    }

    // MARK: Public

    /// Whether the machine had a route when the system last said.
    /// True until told otherwise, so nothing waits on a first
    /// answer to do its work.
    public var isOnline: Bool {
        online.withLock { $0 != .offline }
    }

    /// Every change in whether the machine has a route. The first
    /// reading arrives too, so a launch with no network says so
    /// rather than waiting for the connection to drop.
    public func changes() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let satisfied = path.status == .satisfied
                // Nil is "never asked", so the first reading is news
                // whichever way it goes.
                let seen: Reachability = satisfied ? .online : .offline
                let isNews = self.online.withLock { held in
                    let changed = held != seen
                    held = seen
                    return changed
                }
                guard isNews else {
                    return
                }

                continuation.yield(satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: Self.queue)
        }
    }

    // MARK: Private

    /// Unknown until the system has answered once, which reads as
    /// online, so nothing is held back waiting for a first answer.
    private enum Reachability {
        case unknown
        case online
        case offline
    }

    /// The path monitor's own queue: system callbacks, never the
    /// main actor.
    private static let queue: DispatchQueue = .init(label: "agentide.network-path")

    private let online: Mutex<Reachability> = .init(.unknown)
}
