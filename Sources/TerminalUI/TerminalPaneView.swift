import SwiftTerm
import SwiftUI

/// An embedded terminal running an argv on a local PTY. Closing the
/// view only disconnects this client; tmux sessions keep running in
/// the sandbox.
public struct TerminalPaneView: NSViewRepresentable {
    // MARK: Lifecycle

    /// Creates a terminal that runs an argv; the argv itself decides
    /// its working directory. `onProcessTerminated` fires on the main
    /// actor when the process exits, letting owners show a restart
    /// affordance instead of a dead pane.
    @preconcurrency
    public init(command: [String], onProcessTerminated: (@MainActor () -> Void)? = nil) {
        self.command = command
        self.onProcessTerminated = onProcessTerminated
    }

    // MARK: Public

    /// Bridges process termination back into the view.
    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(onProcessTerminated: (@MainActor () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // The PTY is owned by the terminal view.
        }

        // MARK: Public

        public func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
            // The window owns sizing.
        }

        public func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
            // Titles are not surfaced.
        }

        public func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
            // Directories are not surfaced.
        }

        public func processTerminated(source _: TerminalView, exitCode _: Int32?) {
            onProcessTerminated?()
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

        /// Spawns the process on the first nonzero layout, exactly
        /// once.
        func startWhenSized(_ command: [String], in view: LocalProcessTerminalView) {
            guard started == false else {
                return
            }
            guard view.bounds.height > 0 else {
                observeFrame(command, in: view)
                return
            }

            started = true
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }
            Self.start(command, in: view)
        }

        // MARK: Private

        private static func start(_ command: [String], in view: LocalProcessTerminalView) {
            let resolved = command.first?.hasPrefix("/") == true ? command : ["/usr/bin/env"] + command
            view.startProcess(
                executable: resolved.first ?? "/bin/zsh",
                args: Array(resolved.dropFirst()),
                environment: nil,
                execName: nil,
            )
        }

        private func observeFrame(_ command: [String], in view: LocalProcessTerminalView) {
            guard frameObserver == nil else {
                return
            }

            // The view rides the coordinator rather than the closure:
            // capturing a non-Sendable view in the notification
            // closure trips region isolation.
            pendingView = view
            pendingCommand = command
            view.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: view,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let sized = self.pendingView else {
                        return
                    }

                    self.startWhenSized(self.pendingCommand, in: sized)
                }
            }
        }
    }

    /// Builds the SwiftTerm view and themes it; the process starts
    /// as soon as layout gives the view its real size, otherwise
    /// tmux sized itself to the placeholder frame and drew half a
    /// pane until something forced a resize.
    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = CodeStyle.nsFont
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
        return view
    }

    /// Re-themes when the appearance actually changes; the start
    /// also retries here as a fallback.
    public func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
    }

    /// Creates the process-lifecycle coordinator.
    public func makeCoordinator() -> Coordinator {
        Coordinator(onProcessTerminated: onProcessTerminated)
    }

    // MARK: Private

    private let command: [String]
    private let onProcessTerminated: (@MainActor () -> Void)?

    /// Black on white in light mode, white on black in dark mode; the
    /// app's one terminal look.
    private func applyTheme(to view: LocalProcessTerminalView, context: Context) {
        let scheme = context.environment.colorScheme
        guard context.coordinator.appliedScheme != scheme else {
            return
        }

        context.coordinator.appliedScheme = scheme
        view.nativeBackgroundColor = scheme == .dark ? .black : .white
        view.nativeForegroundColor = scheme == .dark ? .white : .black
    }
}
