import Foundation

/// Tells a GitHub outage from a real failure.
///
/// The difference matters because the answers differ: an outage is
/// waited out, showing what was already fetched, while a genuine
/// failure (no such pull request, bad credentials, a rejected push)
/// needs the user. Reporting every doomed request during an outage
/// buries the second kind under the first.
public enum GitHubOutage {
    // MARK: Public

    /// Whether a failure reads as GitHub being unavailable rather
    /// than the request being wrong: its own 5xx replies, the
    /// GraphQL gateway's overload message, and the network failing
    /// to reach it at all.
    public static func isLikely(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    /// Whether an error reads that way; errors cross module
    /// boundaries as their descriptions.
    public static func isLikely(_ error: any Error) -> Bool {
        isLikely(error.localizedDescription)
    }

    // MARK: Private

    /// Deliberately narrow: anything not listed counts as a real
    /// failure and reaches the user, since silence about a broken
    /// request is worse than noise about an outage.
    private static let markers = [
        "http 500", "http 502", "http 503", "http 504",
        "no server is currently available",
        "service unavailable",
        "bad gateway",
        "gateway timeout",
        "timed out",
        "could not resolve host",
        "connection refused",
        "network is unreachable",
        "the internet connection appears to be offline",
    ]
}
