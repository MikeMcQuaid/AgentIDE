import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - TerminalPaneView

/// An embedded terminal running an argv on a local PTY, with an
/// optional native scrollback viewer. Closing the view only
/// disconnects this client; tmux sessions keep running.
///
/// Selection, copying and the wheel are native: tmux mouse reporting
/// is off, so dragging selects like any Mac text and Cmd-C copies.
/// Wheel-up opens the scrollback viewer (tmux draws on the alternate
/// screen, so the terminal itself has no scrollback to show), except
/// while a pager runs, when wheel events reach it as arrow keys.
public struct TerminalPaneView: View {
    // MARK: Lifecycle

    /// Creates a terminal that runs an argv; the argv itself decides
    /// its working directory. `reflowsCopies` reflows multi-line
    /// copies for pasting into prose tools. `history` enables the
    /// scrollback viewer; `pagerProbe` reports whether a pager is
    /// frontmost, routing wheel events to it instead.
    /// `onProcessTerminated` fires on the main actor when the
    /// process exits, letting owners show a restart affordance.
    @preconcurrency
    public init(
        command: [String],
        reflowsCopies: Bool = false,
        history: (@MainActor () async -> String)? = nil,
        pagerProbe: (@MainActor () async -> Bool)? = nil,
        onProcessTerminated: (@MainActor () -> Void)? = nil,
    ) {
        self.command = command
        self.reflowsCopies = reflowsCopies
        self.history = history
        self.pagerProbe = pagerProbe
        self.onProcessTerminated = onProcessTerminated
    }

    // MARK: Public

    public var body: some View {
        ZStack {
            TerminalRepresentable(
                command: command,
                reflowsCopies: reflowsCopies,
                historyShowing: showsHistory,
                pagerProbe: pagerProbe,
                onHistoryRequest: history == nil ? nil : { showsHistory = true },
                onProcessTerminated: onProcessTerminated,
            )
            if showsHistory, let history {
                TerminalHistoryView(capture: history) { showsHistory = false }
            }
        }
    }

    // MARK: Private

    @State private var showsHistory = false

    private let command: [String]
    private let reflowsCopies: Bool
    private let history: (@MainActor () async -> String)?
    private let pagerProbe: (@MainActor () async -> Bool)?
    private let onProcessTerminated: (@MainActor () -> Void)?
}

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour; wheel
/// routing lives in the coordinator's event monitor, because
/// SwiftTerm's scroll handling is not overridable.
final class PaneTerminalView: LocalProcessTerminalView {
    // MARK: Lifecycle

    deinit {
        // The coordinator owns the event monitor.
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

/// Bridges the SwiftTerm view into SwiftUI and owns the process
/// lifecycle.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    /// Bridges process termination and wheel probing.
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(
            pagerProbe: (@MainActor () async -> Bool)?,
            onHistoryRequest: (() -> Void)?,
            onProcessTerminated: (@MainActor () -> Void)?,
        ) {
            self.pagerProbe = pagerProbe
            self.onHistoryRequest = onHistoryRequest
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // The PTY is owned by the terminal view; the wheel
            // monitor is removed on dismantle.
        }

        // MARK: Internal

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        /// Whether the process has been spawned; it waits for real
        /// bounds so tmux sizes to the pane, not a placeholder frame.
        var started = false

        /// Watches for the first real layout, so the start is
        /// immediate rather than waiting for an unrelated SwiftUI
        /// update.
        var frameObserver: NSObjectProtocol?

        /// What the observer starts once the view has real bounds.
        weak var pendingView: LocalProcessTerminalView?
        var pendingCommand: [String] = []

        let onProcessTerminated: (@MainActor () -> Void)?

        /// Whether the scrollback viewer covers the pane; wheel
        /// events then pass straight through so the viewer scrolls.
        var historyShowing = false

        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
            // The window owns sizing.
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

        /// Intercepts wheel events over the terminal: while a pager
        /// runs they pass through (SwiftTerm's alternate-screen
        /// handling turns them into arrow keys); otherwise wheel-up
        /// accumulates to a threshold and opens the scrollback
        /// viewer, and everything else is swallowed so shells and
        /// agent composers never receive surprise arrow keys.
        func installWheelMonitor(for view: PaneTerminalView) {
            guard wheelMonitor == nil, onHistoryRequest != nil else {
                return
            }

            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, historyShowing == false,
                      event.window === view.window
                else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else {
                    return event
                }

                return route(event, in: view)
            }
        }

        func removeWheelMonitor() {
            if let wheelMonitor {
                NSEvent.removeMonitor(wheelMonitor)
            }
            wheelMonitor = nil
        }

        /// Spawns the process on the first nonzero layout, exactly
        /// once.
        func startWhenSized(_ command: [String], in view: LocalProcessTerminalView) {
            guard started == false else {
                return
            }

            if view.frame.size.width > 1, view.frame.size.height > 1 {
                started = true
                Self.start(command, in: view)
            } else {
                observeFrame(command, in: view)
            }
        }

        // MARK: Private

        /// Roughly two wheel notches, so a stray tick does not open
        /// the viewer.
        private static let historyThreshold: CGFloat = 40

        private let pagerProbe: (@MainActor () async -> Bool)?
        private let onHistoryRequest: (() -> Void)?
        private var lastProbeAt: Date = .distantPast
        private var pagerFrontmost = false
        private var historyAccumulator: CGFloat = 0
        private var wheelMonitor: Any?

        private static func start(_ command: [String], in view: LocalProcessTerminalView) {
            // Non-absolute commands (sudo, tmux) resolve through env:
            // spawning needs a path, not a name.
            let resolved = command.first?.hasPrefix("/") == true ? command : ["/usr/bin/env"] + command
            view.startProcess(
                executable: resolved.first ?? "/bin/zsh",
                args: Array(resolved.dropFirst()),
                environment: nil,
                execName: nil,
            )
        }

        /// Refreshes the pager answer, throttled so wheel streams
        /// cost one query a second.
        private func route(_ event: NSEvent, in _: PaneTerminalView) -> NSEvent? {
            if let pagerProbe, Date().timeIntervalSince(lastProbeAt) > 1 {
                lastProbeAt = Date()
                Task { [weak self] in
                    self?.pagerFrontmost = await pagerProbe()
                }
            }
            guard pagerFrontmost == false else {
                return event
            }
            guard event.scrollingDeltaY > 0 else {
                historyAccumulator = 0
                return nil
            }

            historyAccumulator += event.scrollingDeltaY
            if historyAccumulator > Self.historyThreshold {
                historyAccumulator = 0
                onHistoryRequest?()
            }
            return nil
        }

        private func observeFrame(_ command: [String], in view: LocalProcessTerminalView) {
            pendingView = view
            pendingCommand = command
            view.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: view,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.started == false, let sized = self.pendingView,
                          sized.frame.size.width > 1, sized.frame.size.height > 1
                    else {
                        return
                    }

                    // startWhenSized marks `started` itself; setting
                    // it here first made its guard bail and no
                    // process ever spawned.
                    if let observer = self.frameObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self.frameObserver = nil
                    }
                    self.startWhenSized(self.pendingCommand, in: sized)
                }
            }
        }
    }

    let command: [String]
    let reflowsCopies: Bool
    let historyShowing: Bool
    let pagerProbe: (@MainActor () async -> Bool)?
    let onHistoryRequest: (() -> Void)?
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Removes the wheel monitor with the view.
    static func dismantleNSView(_: PaneTerminalView, coordinator: Coordinator) {
        coordinator.removeWheelMonitor()
    }

    /// Builds the SwiftTerm view and themes it; the process starts
    /// as soon as layout gives the view its real size, otherwise
    /// tmux sized itself to the placeholder frame and drew half a
    /// pane until something forced a resize.
    func makeNSView(context: Context) -> PaneTerminalView {
        let view = PaneTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = CodeStyle.nsFont
        view.reflowsCopies = reflowsCopies
        context.coordinator.installWheelMonitor(for: view)
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
        return view
    }

    /// Re-themes when the appearance actually changes; the start
    /// also retries here as a fallback.
    func updateNSView(_ view: PaneTerminalView, context: Context) {
        context.coordinator.historyShowing = historyShowing
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
    }

    /// Creates the process-lifecycle coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(
            pagerProbe: pagerProbe,
            onHistoryRequest: onHistoryRequest,
            onProcessTerminated: onProcessTerminated,
        )
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
