import Observation
import WebKit

// MARK: - BrowserPane

/// One embedded browser page that is loaded right now: what it shows
/// and the web process rendering it, so pages can be watched and
/// closed beside the sessions in the manager.
public struct BrowserPane: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a pane record.
    public init(worktreePath: String, address: String, processIdentifier: Int32) {
        self.worktreePath = worktreePath
        self.address = address
        self.processIdentifier = processIdentifier
    }

    // MARK: Public

    /// The worktree whose pane this is, and its identity: each
    /// worktree has at most one browser.
    public let worktreePath: String

    /// What it has loaded, empty for a blank page.
    public let address: String

    /// The web content process, zero when WebKit has not started one
    /// or no longer says which it is.
    public let processIdentifier: Int32

    public var id: String {
        worktreePath
    }
}

// MARK: - BrowserPanes

/// Every browser page loaded right now. Pages stay mounted while
/// other worktrees are worked in, so something has to say what they
/// are costing and let them be closed.
@preconcurrency
@Observable
@MainActor
public final class BrowserPanes {
    // MARK: Lifecycle

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Public

    /// The one register of loaded pages, which the manager lists.
    public static let shared: BrowserPanes = .init()

    /// The loaded pages, by worktree.
    public private(set) var all: [BrowserPane] = []

    /// The web content process of a view, nil when WebKit does not
    /// answer for it: the answer is not part of the framework's
    /// public surface, so it is asked for only when the view says it
    /// understands the question, and its absence costs the row its
    /// figures rather than the app anything.
    public static func processIdentifier(of view: WKWebView) -> Int32? {
        // The runtime answers with a bridged number, which is what
        // asking a framework a question it does not publish costs.
        // swiftlint:disable:next legacy_objc_type
        let identifier = (view.value(forKey: Self.processKey) as? NSNumber)?.int32Value
        guard view.responds(to: Selector((Self.processKey))), let identifier, identifier > 0 else {
            return nil
        }

        return identifier
    }

    /// Records what a worktree's browser is showing.
    public func record(_ pane: BrowserPane) {
        if let index = all.firstIndex(where: { $0.worktreePath == pane.worktreePath }) {
            all[index] = pane
        } else {
            all.append(pane)
        }
    }

    /// Forgets a browser whose pane has gone.
    public func remove(worktreePath: String) {
        all.removeAll { $0.worktreePath == worktreePath }
    }

    // MARK: Private

    /// WebKit's own name for the process behind a view.
    private static let processKey = "_webProcessIdentifier"
}
