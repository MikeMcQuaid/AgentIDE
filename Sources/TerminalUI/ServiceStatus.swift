import AgentIDEData
import Foundation
import Observation

/// Whether GitHub is answering, so an outage is reported once and
/// waited out rather than retried and re-reported per request.
///
/// Polling asks about every branch of every repository, so a single
/// outage otherwise fills the messages pane with the same failure
/// dozens of times a minute and keeps hammering a service that is
/// already down. Everything fetched before an outage stays on
/// screen: stale pull request state is far more useful than none.
@preconcurrency
@Observable
@MainActor
public final class ServiceStatus {
    // MARK: Lifecycle

    private init() {
        // One status for the whole app.
    }

    deinit {
        // The status lives for the process.
    }

    // MARK: Public

    /// The one status every GitHub caller reports through.
    public static let shared: ServiceStatus = .init()

    /// Whether GitHub last failed in a way that reads as an outage;
    /// callers poll far less while this holds.
    public private(set) var isUnavailable = false

    /// When the outage was first noticed, for saying how long the
    /// shown state has been stale.
    public private(set) var unavailableSince: Date?

    /// Whether the machine has a route out at all, which is a
    /// different thing from GitHub being down and reads differently
    /// in the messages pane.
    public private(set) var hasNetwork = true

    /// Records a failure. An outage is announced once and then kept
    /// quiet; anything else is a real failure and always reported,
    /// since a broken request the user could fix must not be
    /// swallowed by an outage's silence.
    public func record(failure error: any Error, doing what: String) {
        // A machine with no route explains every failure at once and
        // has said so already: repeating it per branch per poll is
        // what buried the pane.
        guard hasNetwork else {
            return
        }
        guard GitHubOutage.isLikely(error) else {
            ErrorLog.shared.report(what + ": " + error.localizedDescription)
            return
        }
        guard isUnavailable == false else {
            return
        }

        isUnavailable = true
        unavailableSince = Date()
        ErrorLog.shared.report(
            "GitHub is not answering, so pull request state is what was last fetched. "
                + "Retrying quietly; the first success says so. (" + error.localizedDescription + ")",
        )
    }

    /// Told what the system's path monitor sees. Losing the network
    /// is announced once and everything GitHub waits, since nothing
    /// can succeed until it is back; regaining it clears the wait so
    /// the next poll asks straight away.
    public func networkChanged(isOnline: Bool) {
        guard isOnline != hasNetwork else {
            return
        }

        hasNetwork = isOnline
        guard isOnline else {
            isUnavailable = true
            unavailableSince = unavailableSince ?? Date()
            ErrorLog.shared.report(
                "No network connection, so pull request state is what was last fetched. "
                    + "It refreshes by itself the moment the network is back.",
            )
            return
        }

        let since = unavailableSince
        isUnavailable = false
        unavailableSince = nil
        let waited = since.map { " after " + Self.duration(since: $0) } ?? ""
        ErrorLog.shared.note("The network is back" + waited + "; pull request state is refreshing.")
    }

    /// Records a success, which ends an outage and says so once.
    public func recordSuccess() {
        guard isUnavailable else {
            return
        }

        let since = unavailableSince
        isUnavailable = false
        unavailableSince = nil
        let waited = since.map { " after " + Self.duration(since: $0) } ?? ""
        ErrorLog.shared.note("GitHub is answering again" + waited + "; pull request state is refreshing.")
    }

    // MARK: Private

    private static let secondsPerMinute = 60.0

    /// A rough human duration; the exact seconds of an outage are
    /// nobody's business.
    private static func duration(since start: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(start) / secondsPerMinute)
        switch minutes {
        case 0:
            return "less than a minute"

        case 1:
            return "a minute"

        default:
            return String(minutes) + " minutes"
        }
    }
}
