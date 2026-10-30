import Foundation

/// What every network call answers while the machine has no route.
///
/// One refusal for all of them, and one this app already knows to
/// pool: `GitHubOutage` reads it as an outage, so the messages pane
/// says it once rather than once per branch per poll, and nothing is
/// spawned that could only fail.
struct OfflineError: LocalizedError {
    // MARK: Lifecycle

    /// Creates the refusal, naming the work that wanted the network.
    init(doing what: String) {
        self.what = what
    }

    // MARK: Internal

    var errorDescription: String? {
        what + " needs the network, and there is no route to the network right now."
    }

    // MARK: Private

    private let what: String
}
