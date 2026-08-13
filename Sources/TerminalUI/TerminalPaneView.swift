import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - TerminalPaneView

/// An embedded terminal running an argv on a local PTY. Closing the
/// view only disconnects this client; tmux sessions keep running.
///
/// The terminal is deliberately taller than the visible pane and
/// sits in a scroll view: tmux believes the pane is that tall, so
/// recent history stays on the live screen where the wheel scrolls
/// it natively and dragging selects it like any Mac text, with no
/// modal copy-mode and no separate viewer. The view follows the
/// cursor as output arrives unless the user has scrolled away.
public struct TerminalPaneView: View {
    // MARK: Lifecycle

    /// Creates a terminal that runs an argv; the argv itself decides
    /// its working directory. `reflowsCopies` reflows multi-line
    /// copies for pasting into prose tools. `onProcessTerminated`
    /// fires on the main actor when the process exits, letting
    /// owners show a restart affordance instead of a dead pane.
    @preconcurrency
    public init(
        command: [String],
        reflowsCopies: Bool = false,
        onProcessTerminated: (@MainActor () -> Void)? = nil,
    ) {
        self.command = command
        self.reflowsCopies = reflowsCopies
        self.onProcessTerminated = onProcessTerminated
    }

    // MARK: Public

    public var body: some View {
        TerminalRepresentable(
            command: command,
            reflowsCopies: reflowsCopies,
            onProcessTerminated: onProcessTerminated,
        )
    }

    // MARK: Private

    private let command: [String]
    private let reflowsCopies: Bool
    private let onProcessTerminated: (@MainActor () -> Void)?
}

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour.
final class PaneTerminalView: LocalProcessTerminalView {
    // MARK: Lifecycle

    deinit {
        // The PTY dies with the view.
    }

    // MARK: Internal

    /// Reflows multi-line copies for pasting into prose tools.
    var reflowsCopies = false

    /// Native selection copy, reflowed for prose panes.
    override func copy(_ sender: Any) {
        super.copy(sender)
        guard reflowsCopies,
              let text = NSPasteboard.general.string(forType: .string),
              text.contains("\n")
        else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(PasteableText.reflow(text), forType: .string)
    }
}

// MARK: - TerminalRepresentable

/// Bridges the scrolling terminal into SwiftUI and owns the process
/// lifecycle, sizing and cursor following.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    /// Owns layout, spawn timing and the cursor-follow timer.
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(command: [String], onProcessTerminated: (@MainActor () -> Void)?) {
            self.command = command
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // Cleanup happens in dismantleNSView, on the main actor.
        }

        // MARK: Internal

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        weak var terminalView: PaneTerminalView?

        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
            // The scroll view owns sizing.
        }

        func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
            // Titles are not surfaced.
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
            // Directories are not surfaced.
        }

        func processTerminated(source _: TerminalView, exitCode _: Int32?) {
            onProcessTerminated?()
        }

        /// Hooks the scroll view once and watches its size: the
        /// terminal is kept one scrollback taller than the viewport,
        /// and the process starts on the first real layout so tmux
        /// sizes to the pane, not a placeholder frame.
        func configure(scrollView: NSScrollView) {
            guard self.scrollView == nil else {
                return
            }

            self.scrollView = scrollView
            scrollView.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layout()
                }
            }
            followTimer = Timer.scheduledTimer(withTimeInterval: Self.followInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.followCursor()
                }
            }
            // The terminal view's own wheel handling turns scrolling
            // into arrow keys on the alternate screen and is not
            // overridable, so wheel events over the pane are taken
            // before dispatch and given to the scroll view, which
            // keeps momentum and elasticity.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
            ) { [weak self, weak scrollView] event in
                guard let self, let scrollView, event.window === scrollView.window else {
                    return event
                }

                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else {
                    return event
                }

                scrollView.scrollWheel(with: event)
                userScrolledAt = Date()
                return nil
            }
        }

        /// Stops the follow timer and frame observation with the
        /// view.
        func tearDown() {
            followTimer?.invalidate()
            followTimer = nil
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
            if let wheelMonitor {
                NSEvent.removeMonitor(wheelMonitor)
            }
            wheelMonitor = nil
        }

        /// Sizes the terminal to the viewport plus the scrollback
        /// band and spawns the process once the size is real.
        func layout() {
            guard let scrollView, let terminalView else {
                return
            }

            let viewport = scrollView.bounds.size
            guard viewport.width > 1, viewport.height > 1 else {
                return
            }

            let target = NSSize(width: viewport.width, height: viewport.height * Self.heightMultiplier)
            if terminalView.frame.size != target {
                terminalView.setFrameSize(target)
            }
            if started == false {
                started = true
                Self.start(command, in: terminalView)
                lastCursorRow = -1
            }
        }

        // MARK: Private

        /// How much taller than the viewport tmux believes the pane
        /// is: the live screen doubles as natively scrollable
        /// history. Taller makes full-screen redraws costlier.
        private static let heightMultiplier: CGFloat = 10

        private static let followInterval: TimeInterval = 0.5

        /// How long after a manual scroll the cursor follow stays
        /// paused, so reading is never yanked back down.
        private static let followPause: TimeInterval = 1

        private let command: [String]
        private let onProcessTerminated: (@MainActor () -> Void)?
        private weak var scrollView: NSScrollView?
        private var frameObserver: NSObjectProtocol?
        private var followTimer: Timer?
        private var wheelMonitor: Any?
        private var started = false
        private var lastCursorRow = -1
        private var userScrolledAt: Date = .distantPast

        private static func start(_ command: [String], in view: LocalProcessTerminalView) {
            // Non-absolute commands (sudo, tmux) resolve through
            // env: spawning needs a path, not a name.
            let resolved = command.first?.hasPrefix("/") == true ? command : ["/usr/bin/env"] + command
            view.startProcess(
                executable: resolved.first ?? "/bin/zsh",
                args: Array(resolved.dropFirst()),
                environment: nil,
                execName: nil,
            )
        }

        /// Scrolls the cursor's row into view when it moves, unless
        /// the user has scrolled away from where it last was; coming
        /// back re-engages following on the next move.
        private func followCursor() {
            guard started, let scrollView, let terminalView,
                  Date().timeIntervalSince(userScrolledAt) > Self.followPause
            else {
                return
            }

            let terminal = terminalView.getTerminal()
            let row = terminal.getCursorLocation().y
            guard row != lastCursorRow, terminal.rows > 0 else {
                return
            }

            let wasFollowing = lastCursorRow < 0
                || scrollView.documentVisibleRect.intersects(rect(ofRow: lastCursorRow))
            lastCursorRow = row
            if wasFollowing {
                terminalView.scrollToVisible(rect(ofRow: row))
            }
        }

        /// One row's rectangle in the terminal view's coordinates,
        /// which have their origin at the bottom.
        private func rect(ofRow row: Int) -> CGRect {
            guard let terminalView else {
                return .zero
            }

            let rows = max(terminalView.getTerminal().rows, 1)
            let height = terminalView.frame.height / CGFloat(rows)
            let fromTop = CGFloat(row) * height
            return CGRect(
                x: 0,
                y: terminalView.frame.height - fromTop - height,
                width: 1,
                height: height,
            )
        }
    }

    let command: [String]
    let reflowsCopies: Bool
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Stops the coordinator's timer and observers with the view.
    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Builds the terminal inside a scroll view and themes it.
    func makeNSView(context: Context) -> NSScrollView {
        let terminal = PaneTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = CodeStyle.nsFont
        terminal.reflowsCopies = reflowsCopies
        context.coordinator.terminalView = terminal

        let scrollView = NSScrollView()
        scrollView.documentView = terminal
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        context.coordinator.configure(scrollView: scrollView)
        applyTheme(to: terminal, context: context)
        context.coordinator.layout()
        return scrollView
    }

    /// Re-themes when the appearance actually changes; layout also
    /// retries here as a fallback.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let terminal = scrollView.documentView as? PaneTerminalView {
            applyTheme(to: terminal, context: context)
        }
        context.coordinator.layout()
    }

    /// Creates the lifecycle coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(command: command, onProcessTerminated: onProcessTerminated)
    }

    // MARK: Private

    /// Black on white in light mode, white on black in dark mode; the
    /// app's one terminal look.
    private func applyTheme(to view: PaneTerminalView, context: Context) {
        let scheme = context.environment.colorScheme
        guard context.coordinator.appliedScheme != scheme else {
            return
        }

        context.coordinator.appliedScheme = scheme
        view.nativeBackgroundColor = scheme == .dark ? .black : .white
        view.nativeForegroundColor = scheme == .dark ? .white : .black
    }
}
