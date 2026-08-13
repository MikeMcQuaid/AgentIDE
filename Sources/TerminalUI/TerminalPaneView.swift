import AgentIDEDomain
import SwiftTerm
import SwiftUI

// MARK: - TerminalPaneView

/// An embedded terminal running an argv on a local PTY. Closing the
/// view only disconnects this client; tmux sessions keep running.
/// The mouse belongs to tmux: the wheel scrolls tmux history,
/// dragging copies through copy-mode and OSC 52, and Shift-drag
/// falls back to a local selection with Cmd-C.
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

/// Bridges the SwiftTerm view into SwiftUI and owns the process
/// lifecycle.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    /// Bridges process termination back into the view.
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        // MARK: Lifecycle

        init(onProcessTerminated: (@MainActor () -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        deinit {
            // The PTY is owned by the terminal view.
        }

        // MARK: Internal

        /// The last applied appearance; re-applying identical colours
        /// on every SwiftUI update forces needless full redraws.
        var appliedScheme: ColorScheme?

        /// Retains the copy reflower the view only holds weakly as
        /// its delegate; deliberately strong for exactly that reason.
        var copyReflower: ReflowingCopyDelegate?

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

        /// Spawns the process on the first nonzero layout, exactly
        /// once, so tmux sizes to the pane rather than a placeholder
        /// frame.
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

        private let onProcessTerminated: (@MainActor () -> Void)?
        private var started = false
        private var frameObserver: NSObjectProtocol?
        private weak var pendingView: LocalProcessTerminalView?
        private var pendingCommand: [String] = []

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
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Builds the SwiftTerm view and themes it; the process starts
    /// as soon as layout gives the view its real size.
    func makeNSView(context: Context) -> PaneTerminalView {
        let view = PaneTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = CodeStyle.nsFont
        view.reflowsCopies = reflowsCopies
        if reflowsCopies {
            // The delegate is weakly held by the view, so the
            // coordinator keeps it alive.
            let reflower = ReflowingCopyDelegate(base: view)
            context.coordinator.copyReflower = reflower
            view.terminalDelegate = reflower
        }
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
        return view
    }

    /// Re-themes when the appearance actually changes; the start
    /// also retries here as a fallback.
    func updateNSView(_ view: PaneTerminalView, context: Context) {
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
    }

    /// Creates the process-lifecycle coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessTerminated: onProcessTerminated)
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
