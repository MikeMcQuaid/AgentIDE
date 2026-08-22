import Foundation
import Observation

/// The app-wide message log: every surface reports failures and
/// noteworthy statuses here, so they collect in one copyable pane
/// instead of scattering short status lines around the window.
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

    /// A button a message offers: somewhere the fix lives.
    public struct Action: Sendable {
        // MARK: Lifecycle

        public init(label: String, url: URL) {
            self.label = label
            self.url = url
        }

        // MARK: Public

        public let label: String
        public let url: URL
    }

    /// One reported message.
    public struct Entry: Identifiable, Sendable {
        /// The entry's position in the log.
        public let id: Int

        /// When the message was reported.
        public let date: Date

        /// The full message or output.
        public let message: String

        /// Whether the message is a failure; only failures count in
        /// the tab's badge and summon the tab.
        public let isError: Bool

        /// The fix the message offers, when one is a click away.
        public let action: Action?
    }

    /// The one log the whole app reports into.
    public static let shared: ErrorLog = .init()

    /// The messages reported this session, oldest first.
    public private(set) var entries: [Entry] = []

    /// How many failures the log holds, for the tab's badge; plain
    /// status notes deliberately carry no number.
    public var errorCount: Int {
        entries.count { $0.isError }
    }

    /// Appends a failure to the log, dropping the oldest entries
    /// beyond the cap so a noisy session never grows without bound.
    public func report(_ message: String, action: Action? = nil) {
        append(message, isError: true, action: action)
    }

    /// Appends a status note: visible in the pane, never badged and
    /// never summoning the tab.
    public func note(_ message: String) {
        append(message, isError: false)
    }

    /// Empties the log; the messages tab stays either way.
    public func clear() {
        entries = []
    }

    // MARK: Private

    /// Kept small: the pane is for recent failures, not an archive.
    private static let entryCap = 500

    /// Monotonic, so identities survive the cap dropping entries.
    private var nextID = 0

    private func append(_ message: String, isError: Bool, action: Action? = nil) {
        nextID += 1
        entries.append(Entry(id: nextID, date: Date(), message: message, isError: isError, action: action))
        if entries.count > Self.entryCap {
            entries.removeFirst(entries.count - Self.entryCap)
        }
    }
}
