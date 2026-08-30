import AgentIDEData
import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - TerminalRepresentable.Coordinator

extension TerminalRepresentable {
    /// Runs the pane's transport. For agent panes that is the herdr
    /// terminal stream: feeding rendered frames into the view and
    /// forwarding keystrokes, pastes, resizes and the wheel back to
    /// herdr. For the shell pane it just watches the local process.
    final class Coordinator: NSObject, TerminalViewDelegate, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(onProcessTerminated: (@MainActor () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // tearDown owns teardown, via dismantleNSView.
        }

        // MARK: Internal

        /// How long the pane waits for its first frame before
        /// reporting the launch chain; frames keep being accepted
        /// afterwards, so a slow attach recovers by itself.
        static let frameTimeoutSeconds = 5

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        var onProcessTerminated: (@MainActor () -> Void)?
        var tornDown = false
        var exitReason: String?
        weak var view: PaneTerminalView?
        var channel: HerdrTerminalChannel?
        var framesSeen = 0
        var frameDeadline: Task<Void, Never>?

        /// The Option-drag selector, owned by its event monitor.
        weak var blockSelector: BlockSelector?

        /// Installs the Option-drag rectangular selection and the
        /// wheel routing: both arrive through a monitor because
        /// SwiftTerm's mouse handling is not overridable.
        func installBlockSelection(on view: PaneTerminalView) {
            guard blockMonitor == nil else {
                return
            }

            // The monitor's closure is the selector's owner: it
            // captures it strongly and tearDown releases both. The
            // coordinator keeps a weak hold so output can move a
            // held selection with the text under it.
            let selector = BlockSelector(view: view)
            blockSelector = selector
            blockMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel],
            ) { [weak view] event in
                guard let view, event.window === view.window else {
                    return event
                }
                guard event.type != .scrollWheel else {
                    return view.routeWheel(event)
                }

                return selector.handle(event)
            }
        }

        /// Releases the controller and removes the event monitor
        /// with the view; the herdr workspace itself keeps running.
        func tearDown() {
            if let blockMonitor {
                NSEvent.removeMonitor(blockMonitor)
            }
            blockMonitor = nil
            tornDown = true
            frameDeadline?.cancel()
            frameDeadline = nil
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
        /// transport, so the herdr client or shell sizes to the pane
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

            channel?.send(HerdrTerminal.resizeCommand(columns: newCols, rows: newRows))
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

        /// Only web links open. SwiftTerm resolves a click on any
        /// detected token, a bare file path included, to a link and
        /// asks to open it; its default handed the path to the system
        /// opener, which is Finder answering "-50" mid-selection. A
        /// path is left to be selected and copied, never opened.
        func requestOpenLink(source _: TerminalView, link: String, params _: [String: String]) {
            LinkOpener.openWeb(link)
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
        /// input command, in order.
        private func flushOutgoing() {
            flushScheduled = false
            let bytes = outgoing
            outgoing.removeAll(keepingCapacity: true)
            guard bytes.isEmpty == false else {
                return
            }

            channel?.send(HerdrTerminal.inputCommand(bytes: bytes))
        }

        /// Drops the running client and resets the conversation
        /// state so a new command can attach through the same view;
        /// the terminal clears via a full reset so the old session's
        /// screen never shows over the new one.
        private func discardClient(of view: PaneTerminalView) {
            frameDeadline?.cancel()
            frameDeadline = nil
            pump?.cancel()
            pump = nil
            if let channel {
                Task {
                    await channel.stop()
                }
            }
            channel = nil
            framesSeen = 0
            exitReason = nil
            started = false
            view.feed(text: "\u{1B}c")
        }

        private func start(_ transport: TerminalTransport, in view: PaneTerminalView) {
            self.view = view
            switch transport {
            case let .control(command):
                // The wheel goes to herdr, which owns the scrollback
                // and repaints the viewport scrolled; the local
                // buffer only ever holds the rendered screen.
                view.onScroll = { [weak self] upwards, lines in
                    self?.channel?.send(HerdrTerminal.scrollCommand(upwards: upwards, lines: lines))
                }
                startControl(command, in: view)

            case let .shell(directory, environment):
                // A login interactive shell so the user's own config
                // applies; the PTY belongs to the view and dies with
                // it, which is the whole design. The extras join what
                // a terminal always sets, so passing them cannot cost
                // the shell its own variables.
                view.startProcess(
                    executable: "/bin/zsh",
                    args: ["-il"],
                    environment: Terminal.getEnvironmentVariables()
                        + environment.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value },
                    execName: nil,
                    currentDirectory: directory,
                )
            }
        }

        private func startControl(_ command: [String], in view: PaneTerminalView) {
            let attached = HerdrTerminalChannel(command: command)
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
