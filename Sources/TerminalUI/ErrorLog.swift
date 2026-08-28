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
    public func report(_ message: String) {
        append(message, isError: true)
    }

    /// Appends a status note: visible in the pane, never badged and
    /// never summoning the tab.
    public func note(_ message: String) {
        append(message, isError: false)
    }

    /// The same, for work belonging to one repository: the name the
    /// sidebar shows goes in front, since "Pushed" and "Rebased"
    /// read identically whichever repository they happened in.
    public func note(_ message: String, about repository: String) {
        note(Self.prefixed(message, with: repository))
    }

    /// A failure in one repository's work, named the same way.
    public func report(_ message: String, about repository: String) {
        report(Self.prefixed(message, with: repository))
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

    /// The message with its repository in front, unless it is
    /// already there: a name is worth saying once.
    private static func prefixed(_ message: String, with repository: String) -> String {
        guard repository.isEmpty == false, message.hasPrefix(repository + ": ") == false else {
            return message
        }

        return repository + ": " + message
    }

    private func append(_ message: String, isError: Bool) {
        nextID += 1
        entries.append(Entry(id: nextID, date: Date(), message: message, isError: isError))
        if entries.count > Self.entryCap {
            entries.removeFirst(entries.count - Self.entryCap)
        }
    }
}
