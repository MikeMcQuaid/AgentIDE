import Synchronization

// MARK: - HostFacts

/// What one directory of your own last said about itself.
///
/// `Sendable` by inference rather than by annotation: everything it
/// holds is, and an internal type gets the conformance for free,
/// which is why writing it out here is removed again by the
/// formatter as redundant.
struct HostFacts: Hashable {
    /// Whether it was there at all when it was last read.
    let exists: Bool
    let branch: String
    let isDirty: Bool
    let aheadOfUpstream: Int?
}

// MARK: - HostFactsCache

/// The facts each directory of your own last gave, so its row keeps
/// painting while nothing on disk is touched again.
///
/// A directory of your own can be anywhere: inside Documents, on a
/// network volume, on a disk that is not mounted. macOS asks the
/// user before any of those can be read, and asks again every time,
/// so AgentIDE reads one only while it is the row in front of you
/// and remembers what it said for the rest.
final class HostFactsCache: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the dictionary.
    }

    // MARK: Internal

    func facts(of path: String) -> HostFacts? {
        held.withLock { $0[path] }
    }

    func remember(_ facts: HostFacts, of path: String) {
        held.withLock { $0[path] = facts }
    }

    // MARK: Private

    private let held: Mutex<[String: HostFacts]> = .init([:])
}
