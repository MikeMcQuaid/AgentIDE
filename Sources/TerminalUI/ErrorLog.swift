import Foundation
import Observation

/// The app-wide error log: every surface reports failures here, so
/// they collect in one copyable pane instead of scattering short
/// status lines around the window.
@preconcurrency
@Observable
@MainActor
public final class ErrorLog {
    // MARK: Lifecycle

    private init() {
        // One shared log for the whole app.
    }

    deinit {
        // The shared log lives for the whole process.
    }

    // MARK: Public

    /// One reported failure.
    public struct Entry: Identifiable, Sendable {
        /// The entry's position in the log.
        public let id: Int

        /// When the failure was reported.
        public let date: Date

        /// The failure's full message or output.
        public let message: String
    }

    /// The one log the whole app reports into.
    public static let shared: ErrorLog = .init()

    /// The failures reported this session, oldest first.
    public private(set) var entries: [Entry] = []

    /// Whether anything was ever reported this session; the errors
    /// tab appears on the first report and then stays, even across
    /// a clear.
    public private(set) var everReported = false

    /// Appends a failure to the log, dropping the oldest entries
    /// beyond the cap so a noisy session never grows without bound.
    public func report(_ message: String) {
        everReported = true
        nextID += 1
        entries.append(Entry(id: nextID, date: Date(), message: message))
        if entries.count > Self.entryCap {
            entries.removeFirst(entries.count - Self.entryCap)
        }
    }

    /// Empties the log; the errors tab stays for the session.
    public func clear() {
        entries = []
    }

    // MARK: Private

    /// Kept small: the pane is for recent failures, not an archive.
    private static let entryCap = 500

    /// Monotonic, so identities survive the cap dropping entries.
    private var nextID = 0
}
