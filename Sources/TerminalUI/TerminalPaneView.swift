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
/// modal copy-mode and no separate viewer. The scrollable range ends
/// where content ends, growing as output does; a viewport at the
/// bottom sticks to it, and one scrolled away never moves by itself.
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

// MARK: - TerminalRepresentable

/// Bridges the scrolling terminal into SwiftUI and owns the process
/// lifecycle, sizing and the content-extent tracking.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    /// Owns layout, spawn timing and the content-extent timer.
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
        weak var containerView: TerminalClipView?

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

        /// Hooks the scroll view once and watches its size, so the
        /// process starts on the first real layout and tmux sizes to
        /// the pane, not a placeholder frame.
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
            extentTimer = Timer.scheduledTimer(
                withTimeInterval: Self.extentInterval,
                repeats: true,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.trackContent()
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
                return nil
            }
        }

        /// Stops the extent timer and observers with the view.
        func tearDown() {
            extentTimer?.invalidate()
            extentTimer = nil
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
            if let wheelMonitor {
                NSEvent.removeMonitor(wheelMonitor)
            }
            wheelMonitor = nil
        }

        /// Sizes the terminal to a multiple of the viewport inside
        /// its clipping container and spawns the process once the
        /// size is real; a bottom-pinned viewport stays pinned
        /// across resizes.
        func layout() {
            guard let scrollView, let terminalView, let containerView else {
                return
            }

            let viewport = scrollView.bounds.size
            guard viewport.width > 1, viewport.height > 1 else {
                return
            }

            let tall = NSSize(width: viewport.width, height: viewport.height * Self.heightMultiplier)
            if terminalView.frame.size != tall {
                let pinned = isAtBottom
                terminalView.frame = CGRect(origin: .zero, size: tall)
                let height = min(max(containerView.frame.height, viewport.height), tall.height)
                containerView.setFrameSize(NSSize(width: viewport.width, height: height))
                if pinned {
                    scrollToBottom()
                }
            }
            if started == false {
                started = true
                Self.start(command, in: terminalView)
            }
        }

        // MARK: Private

        /// How much taller than the viewport tmux believes the pane
        /// is: the live screen doubles as natively scrollable
        /// history. Taller makes full-screen redraws costlier.
        private static let heightMultiplier: CGFloat = 10

        private static let extentInterval: TimeInterval = 0.5

        /// Rows kept visible below the cursor: composer borders and
        /// status lines sit just under it.
        private static let extentPaddingRows = 4

        /// How close to the content's end still counts as pinned
        /// there.
        private static let bottomTolerance: CGFloat = 4

        private let command: [String]
        private let onProcessTerminated: (@MainActor () -> Void)?
        private weak var scrollView: NSScrollView?
        private var frameObserver: NSObjectProtocol?
        private var extentTimer: Timer?
        private var wheelMonitor: Any?
        private var started = false
        private var candidateRow = -1
        private var positioned = false

        private var isAtBottom: Bool {
            guard let scrollView, let containerView else {
                return true
            }

            return scrollView.documentVisibleRect.maxY >= containerView.frame.height - Self.bottomTolerance
        }

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

        /// Grows and shrinks the scrollable range to where content
        /// ends, judged by where the cursor settles (full-screen
        /// programs park it all over the screen mid-repaint, so a
        /// row must repeat on two samples to count). A viewport at
        /// the bottom sticks to the growing end; one scrolled away
        /// never moves. The first settled row also positions the
        /// viewport once.
        private func trackContent() {
            guard started, let scrollView, let terminalView, let containerView else {
                return
            }

            let terminal = terminalView.getTerminal()
            let row = terminal.getCursorLocation().y
            guard terminal.rows > 0 else {
                return
            }
            guard row == candidateRow else {
                candidateRow = row
                return
            }

            let rowHeight = terminalView.frame.height / CGFloat(terminal.rows)
            let viewport = scrollView.bounds.size
            let content = CGFloat(row + Self.extentPaddingRows) * rowHeight
            let target = min(max(content, viewport.height), terminalView.frame.height)
            if abs(target - containerView.frame.height) > rowHeight {
                let pinned = isAtBottom
                containerView.setFrameSize(NSSize(width: viewport.width, height: target))
                if pinned {
                    scrollToBottom()
                }
            }
            if positioned == false {
                positioned = true
                containerView.scrollToVisible(
                    CGRect(x: 0, y: CGFloat(row) * rowHeight, width: 1, height: rowHeight),
                )
            }
        }

        private func scrollToBottom() {
            guard let scrollView, let containerView else {
                return
            }

            let offset = max(0, containerView.frame.height - scrollView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    let command: [String]
    let reflowsCopies: Bool
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Stops the coordinator's timer and observers with the view.
    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Builds the terminal inside its clipping container inside a
    /// scroll view, and themes it.
    func makeNSView(context: Context) -> NSScrollView {
        let terminal = PaneTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = CodeStyle.nsFont
        terminal.reflowsCopies = reflowsCopies
        context.coordinator.terminalView = terminal

        let container = TerminalClipView(frame: .zero)
        container.clipsToBounds = true
        container.addSubview(terminal)
        context.coordinator.containerView = container

        let scrollView = NSScrollView()
        scrollView.documentView = container
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
    func updateNSView(_: NSScrollView, context: Context) {
        if let terminal = context.coordinator.terminalView {
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
