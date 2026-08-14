import AgentIDEData
import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - CommandExpectation

/// What each pending command's response means; responses arrive
/// strictly in command order.
private enum CommandExpectation {
    case acknowledgement
    case history
}

// MARK: - TerminalRepresentable.Coordinator

extension TerminalRepresentable {
    /// Runs the control mode conversation: seeds the local
    /// scrollback from the pane's history, feeds live output into
    /// the view and forwards keystrokes, pastes and resizes back to
    /// tmux.
    final class Coordinator: NSObject, TerminalViewDelegate {
        // MARK: Lifecycle

        init(onProcessTerminated: (@MainActor () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // tearDown owns teardown, via dismantleNSView.
        }

        // MARK: Internal

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        /// Installs the Option-drag rectangular selection: its
        /// events arrive through a monitor because SwiftTerm's
        /// mouse handling is not overridable.
        func installBlockSelection(on view: PaneTerminalView) {
            guard blockMonitor == nil else {
                return
            }

            // The monitor's closure is the selector's owner: it
            // captures it strongly and tearDown releases both.
            let selector = BlockSelector(view: view)
            blockMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            ) { [weak view] event in
                guard let view, event.window === view.window else {
                    return event
                }

                return selector.handle(event)
            }
        }

        /// Detaches the client and removes the event monitor with
        /// the view; the tmux session itself keeps running.
        func tearDown() {
            if let blockMonitor {
                NSEvent.removeMonitor(blockMonitor)
            }
            blockMonitor = nil
            tornDown = true
            seedDeadline?.cancel()
            seedDeadline = nil
            pump?.cancel()
            onProcessTerminated = nil
            if let channel {
                Task {
                    await channel.stop()
                }
            }
            channel = nil
        }

        /// Attaches on the first nonzero layout, exactly once, so
        /// the tmux client sizes to the pane rather than a
        /// placeholder frame.
        func startWhenSized(_ command: [String], in view: PaneTerminalView) {
            guard started == false else {
                return
            }

            if view.frame.size.width > 1, view.frame.size.height > 1 {
                started = true
                start(command, in: view)
            } else {
                observeFrame(command, in: view)
            }
        }

        func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
            guard channel != nil, newCols > 0, newRows > 0 else {
                return
            }

            sendCommand(TmuxControl.resizeCommand(columns: newCols, rows: newRows), expecting: .acknowledgement)
        }

        func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            guard data.isEmpty == false else {
                return
            }

            sendCommand(TmuxControl.sendKeysCommand(bytes: data), expecting: .acknowledgement)
        }

        func setTerminalTitle(source _: TerminalView, title _: String) {
            // Titles are not surfaced.
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
            // Directories are not surfaced.
        }

        func scrolled(source _: TerminalView, position _: Double) {
            // Scrolling is local to the view.
        }

        func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {
            // Rendering is owned by SwiftTerm.
        }

        // MARK: Private

        /// How long the pane waits for its history before showing
        /// live output anyway.
        private static let seedTimeoutSeconds = 3

        private var onProcessTerminated: (@MainActor () -> Void)?
        private var started = false
        private var tornDown = false
        private var exitReason: String?
        private var blockMonitor: Any?
        private var frameObserver: NSObjectProtocol?
        private weak var pendingView: PaneTerminalView?
        private var pendingCommand: [String] = []

        private weak var view: PaneTerminalView?
        private var channel: TmuxControlChannel?
        private var pump: Task<Void, Never>?

        /// The attach command itself answers with one empty block
        /// before anything this client sends, so the queue starts
        /// with that response accounted for.
        private var pending: [CommandExpectation] = [.acknowledgement]

        /// Output arriving before the history seed, replayed after
        /// it so nothing renders out of order.
        private var queuedOutput: [[UInt8]] = []
        private var seeded = false
        private var seedDeadline: Task<Void, Never>?

        private func start(_ command: [String], in view: PaneTerminalView) {
            self.view = view
            let attached = TmuxControlChannel(command: command)
            channel = attached
            pump = Task { [weak self] in
                guard let stream = try? await attached.start() else {
                    self?.finish()
                    return
                }

                self?.requestInitialState(of: view)
                for await event in stream {
                    self?.handle(event)
                }
                self?.finish()
            }
        }

        /// The pane appears at its history in one round trip: size
        /// the client first so tmux settles the pane's dimensions,
        /// heal the scrollback depth on servers older than their
        /// config, then capture everything scrollback should hold.
        private func requestInitialState(of view: PaneTerminalView) {
            let terminal = view.getTerminal()
            sendCommand(
                TmuxControl.resizeCommand(columns: terminal.cols, rows: terminal.rows),
                expecting: .acknowledgement,
            )
            sendCommand(TmuxControl.historyLimitCommand, expecting: .acknowledgement)
            sendCommand(TmuxControl.historyCommand, expecting: .history)
            // A seed that never answers must not hold the pane blank
            // forever; after the deadline live output flows unseeded.
            seedDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.seedTimeoutSeconds))
                self?.seedIfStalled()
            }
        }

        /// The deadline fired before the history response: report it
        /// and let live output through rather than queueing forever.
        private func seedIfStalled() {
            guard seeded == false, tornDown == false else {
                return
            }

            ErrorLog.shared.report("Terminal: the pane's history never answered; showing live output only")
            seed(lines: [])
        }

        private func sendCommand(_ line: String, expecting: CommandExpectation) {
            pending.append(expecting)
            channel?.send(line)
        }

        private func handle(_ event: TmuxControlEvent) {
            switch event {
            case let .output(_, bytes):
                if seeded {
                    view?.feed(byteArray: bytes[...])
                } else {
                    queuedOutput.append(bytes)
                }

            case let .response(lines, isError):
                guard pending.isEmpty == false, pending.removeFirst() == .history else {
                    return
                }

                seed(lines: isError ? [] : lines)

            case let .exited(reason):
                exitReason = reason

            case .notification:
                break
            }
        }

        /// Feeds the captured history, replays anything queued and
        /// nudges the pane to repaint so full-screen interfaces
        /// redraw themselves over the seeded scrollback.
        private func seed(lines: [String]) {
            let text = TmuxControl.seedText(lines: lines)
            if text.isEmpty == false {
                view?.feed(text: text)
            }
            for bytes in queuedOutput {
                view?.feed(byteArray: bytes[...])
            }
            queuedOutput = []
            seeded = true
            seedDeadline?.cancel()
            seedDeadline = nil
            nudgeRepaint()
        }

        /// A one-row shrink and restore: the resulting window change
        /// makes full-screen interfaces repaint without tmux needing
        /// a redraw command.
        private func nudgeRepaint() {
            guard let terminal = view?.getTerminal() else {
                return
            }

            sendCommand(
                TmuxControl.resizeCommand(columns: terminal.cols, rows: max(terminal.rows - 1, 1)),
                expecting: .acknowledgement,
            )
            sendCommand(
                TmuxControl.resizeCommand(columns: terminal.cols, rows: terminal.rows),
                expecting: .acknowledgement,
            )
        }

        /// The stream ended: surface why when it was not a clean
        /// detach, so a failed attach never renders as a silent
        /// blank pane, then let the owner react.
        private func finish() {
            guard tornDown == false else {
                return
            }

            let callback = onProcessTerminated
            onProcessTerminated = nil
            let reason = exitReason
            let wasSeeded = seeded
            let ended = channel
            channel = nil
            Task { [weak self] in
                let diagnostics = await ended?.collectedErrorText() ?? ""
                let detail = [reason, diagnostics.isEmpty ? nil : diagnostics]
                    .compactMap(\.self)
                    .joined(separator: "; ")
                if detail.isEmpty == false || wasSeeded == false {
                    let message = detail.isEmpty ? "the tmux client exited before attaching" : detail
                    ErrorLog.shared.report("Terminal: " + message)
                    self?.view?.feed(text: "\r\n[tmux client exited: " + message + "]\r\n")
                }
                callback?()
            }
        }

        private func observeFrame(_ command: [String], in view: PaneTerminalView) {
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
                    // client ever attached.
                    if let observer = self.frameObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self.frameObserver = nil
                    }
                    self.startWhenSized(self.pendingCommand, in: sized)
                }
            }
        }
    }
}
