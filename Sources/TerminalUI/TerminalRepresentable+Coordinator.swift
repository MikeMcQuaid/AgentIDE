import AgentIDEData
import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - TerminalRepresentable.Coordinator

extension TerminalRepresentable {
    /// Runs the pane's transport. For agent panes that is the
    /// control mode conversation: seeding local scrollback from the
    /// pane's history, feeding live output into the view and
    /// forwarding keystrokes, pastes and resizes back to tmux. For
    /// the shell pane it just watches the local process.
    final class Coordinator: NSObject, TerminalViewDelegate, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(onProcessTerminated: (@MainActor () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // tearDown owns teardown, via dismantleNSView.
        }

        // MARK: Internal

        /// How long the pane waits for its history before showing
        /// live output anyway.
        static let seedTimeoutSeconds = 3

        /// How many capture asks run before the pane gives up on
        /// its history and reports.
        static let seedAttemptLimit = 3

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        var onProcessTerminated: (@MainActor () -> Void)?
        var tornDown = false
        var exitReason: String?
        weak var view: PaneTerminalView?
        var channel: TmuxControlChannel?
        /// The attach command itself answers with one empty block
        /// before anything this client sends, so the queue starts
        /// with that response accounted for.
        var pending: [CommandExpectation] = [.acknowledgement]

        /// Output arriving before the history seed, replayed after
        /// it so nothing renders out of order.
        var queuedOutput: [[UInt8]] = []
        var seeded = false
        var seedDeadline: Task<Void, Never>?
        var seedAttempts = 0
        var responsesSeen = 0
        var outputsSeen = 0
        var notificationsSeen = 0

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

        /// Attaches on the first nonzero layout, exactly once per
        /// transport, so the tmux client or shell sizes to the pane
        /// rather than a placeholder frame. SwiftUI can reuse the
        /// view for a different command; the old client is
        /// discarded and the new one attaches.
        func startWhenSized(_ transport: TerminalTransport, in view: PaneTerminalView) {
            if started, transport != startedTransport {
                discardClient(of: view)
            }
            guard started == false else {
                return
            }

            if view.frame.size.width > 1, view.frame.size.height > 1 {
                started = true
                startedTransport = transport
                start(transport, in: view)
            } else {
                observeFrame(transport, in: view)
            }
        }

        /// Cmd-K on the shell: a full terminal reset wipes the screen
        /// and local scrollback, then Ctrl-L asks the running shell to
        /// redraw its prompt, which is what a terminal app's clear
        /// does. Each raise of the counter clears once; the first
        /// observed value only records the baseline, so a stale count
        /// from a previous launch never clears on appearance.
        func clearIfRequested(_ request: Int, in view: PaneTerminalView) {
            guard let seen = seenClearRequest else {
                seenClearRequest = request
                return
            }
            guard request != seen else {
                return
            }

            seenClearRequest = request
            view.feed(text: "\u{1B}c")
            view.send(txt: "\u{0C}")
        }

        /// Releases keyboard focus when the pane goes invisible: the
        /// shell stays mounted behind other tabs to survive
        /// switches, and a hidden terminal holding first responder
        /// swallowed keystrokes and pastes meant for the visible
        /// pane.
        func updateFocus(isActive: Bool, of view: PaneTerminalView) {
            guard isActive == false, let window = view.window,
                  let responder = window.firstResponder as? NSView, responder.isDescendant(of: view)
            else {
                return
            }

            window.makeFirstResponder(nil)
        }

        func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
            guard channel != nil, newCols > 0, newRows > 0 else {
                return
            }

            sendCommand(TmuxControl.resizeCommand(columns: newCols, rows: newRows), expecting: .acknowledgement)
        }

        /// Bytes for the pane. A bracketed paste arrives as three
        /// separate sends (start marker, text, end marker); shipped as
        /// three commands, the pieces could straddle the agent's input
        /// reads and Codex dropped the paste as unterminated. Bytes
        /// are therefore gathered for one run loop turn and shipped
        /// as one command, so a paste lands in a single write.
        func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            guard data.isEmpty == false else {
                return
            }

            outgoing.append(contentsOf: data)
            guard flushScheduled == false else {
                return
            }

            flushScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushOutgoing()
            }
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

        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
            // The local shell's PTY resize is handled by the view.
        }

        func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
            // Titles are not surfaced.
        }

        /// The local shell exited; owners show a restart affordance.
        func processTerminated(source _: TerminalView, exitCode _: Int32?) {
            let callback = onProcessTerminated
            onProcessTerminated = nil
            callback?()
        }

        // MARK: Private

        private var started = false
        private var seenClearRequest: Int?
        private var outgoing: [UInt8] = []
        private var flushScheduled = false
        private var startedTransport: TerminalTransport?
        private var blockMonitor: Any?
        private var frameObserver: NSObjectProtocol?
        private weak var pendingView: PaneTerminalView?
        private var pendingTransport: TerminalTransport?

        private var pump: Task<Void, Never>?

        /// Ships everything gathered since the last turn as one
        /// `send-keys`, in order.
        private func flushOutgoing() {
            flushScheduled = false
            let bytes = outgoing
            outgoing.removeAll(keepingCapacity: true)
            guard bytes.isEmpty == false else {
                return
            }

            sendCommand(TmuxControl.sendKeysCommand(bytes: bytes), expecting: .acknowledgement)
        }

        /// Drops the running client and resets the conversation
        /// state so a new command can attach through the same view;
        /// the terminal clears via a full reset so the old session's
        /// screen never shows over the new one.
        private func discardClient(of view: PaneTerminalView) {
            seedDeadline?.cancel()
            seedDeadline = nil
            pump?.cancel()
            pump = nil
            if let channel {
                Task {
                    await channel.stop()
                }
            }
            channel = nil
            pending = [.acknowledgement]
            queuedOutput = []
            seeded = false
            seedAttempts = 0
            responsesSeen = 0
            outputsSeen = 0
            notificationsSeen = 0
            exitReason = nil
            started = false
            view.feed(text: "\u{1B}c")
        }

        private func start(_ transport: TerminalTransport, in view: PaneTerminalView) {
            self.view = view
            switch transport {
            case let .control(command):
                startControl(command, in: view)

            case let .shell(directory):
                // A login interactive shell so the user's own config
                // applies; the PTY belongs to the view and dies with
                // it, which is the whole design.
                view.startProcess(
                    executable: "/bin/zsh",
                    args: ["-il"],
                    environment: nil,
                    execName: nil,
                    currentDirectory: directory,
                )
            }
        }

        private func startControl(_ command: [String], in view: PaneTerminalView) {
            let attached = TmuxControlChannel(command: command)
            channel = attached
            pump = Task { [weak self] in
                guard let stream = try? await attached.start() else {
                    self?.finish(for: attached)
                    return
                }

                self?.requestInitialState(of: view)
                for await event in stream {
                    self?.handle(event, from: attached)
                }
                self?.finish(for: attached)
            }
        }

        private func observeFrame(_ transport: TerminalTransport, in view: PaneTerminalView) {
            pendingView = view
            pendingTransport = transport
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
                    if let awaited = self.pendingTransport {
                        self.startWhenSized(awaited, in: sized)
                    }
                }
            }
        }
    }
}
