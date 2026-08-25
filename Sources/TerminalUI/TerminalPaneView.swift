import SwiftTerm
import SwiftUI

// MARK: - TerminalPaneView

/// An embedded terminal. Agent panes attach to a herdr pane as a
/// terminal controller: herdr streams rendered frames and the view
/// renders them locally, so selection, copying and pasting are all
/// native, and closing the view only releases the controller while
/// the session keeps running. The shell pane runs a plain local
/// shell on the view's own PTY instead: no server, no client, and
/// the shell dies with the app.
public struct TerminalPaneView: View {
    // MARK: Lifecycle

    /// Creates a terminal that spawns a herdr controller argv and
    /// renders the attached pane. `reflowsCopies` reflows multi-line
    /// copies for pasting into prose tools. `isActive` says whether
    /// the pane is the one on screen: an invisible mounted pane must
    /// give up keyboard focus or it swallows keystrokes and pastes
    /// meant for the visible one. `onProcessTerminated` fires on the
    /// main actor when the client exits, letting owners show a
    /// restart affordance instead of a dead pane.
    @preconcurrency
    public init(
        command: [String],
        reflowsCopies: Bool = false,
        isActive: Bool = true,
        onProcessTerminated: (@MainActor () -> Void)? = nil,
    ) {
        transport = .control(command: command)
        self.reflowsCopies = reflowsCopies
        self.isActive = isActive
        self.onProcessTerminated = onProcessTerminated
    }

    /// Creates a terminal running the user's login shell in a
    /// directory on a local PTY. `environment` adds to what a shell
    /// normally inherits, for the editor variables that point back
    /// at the app.
    @preconcurrency
    public init(
        shellIn directory: String,
        environment: [String: String] = [:],
        isActive: Bool = true,
        onProcessTerminated: (@MainActor () -> Void)? = nil,
    ) {
        transport = .shell(directory: directory, environment: environment)
        reflowsCopies = false
        self.isActive = isActive
        self.onProcessTerminated = onProcessTerminated
    }

    // MARK: Public

    public var body: some View {
        TerminalRepresentable(
            transport: transport,
            reflowsCopies: reflowsCopies,
            isActive: isActive,
            clearRequest: clearShellRequest,
            onProcessTerminated: onProcessTerminated,
        )
    }

    // MARK: Private

    /// Cmd-K's counter on the storage bus; only an active local
    /// shell pane acts on it, never an agent pane, so clearing can
    /// never wipe an agent's conversation from view.
    @AppStorage("clearShellRequest")
    private var clearShellRequest = 0

    private let transport: TerminalTransport
    private let reflowsCopies: Bool
    private let isActive: Bool
    private let onProcessTerminated: (@MainActor () -> Void)?
}

// MARK: - TerminalTransport

/// What feeds a terminal pane: a herdr terminal controller's argv,
/// or a local shell's working directory.
enum TerminalTransport: Equatable {
    case control(command: [String])
    case shell(directory: String, environment: [String: String])
}

// MARK: - TerminalRepresentable

/// Bridges the SwiftTerm view into SwiftUI and owns the herdr
/// terminal controller.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    let transport: TerminalTransport
    let reflowsCopies: Bool
    let isActive: Bool
    let clearRequest: Int
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Detaches the coordinator's client with the view.
    static func dismantleNSView(_: PaneTerminalView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Builds the SwiftTerm view and themes it; the client attaches
    /// as soon as layout gives the view its real size.
    func makeNSView(context: Context) -> PaneTerminalView {
        let view = PaneTerminalView(frame: .zero)
        if case .control = transport {
            // The coordinator speaks the control protocol; a local
            // shell keeps the view's own PTY wiring instead.
            view.terminalDelegate = context.coordinator
            view.hideScroller()
            view.dropLocalScrollback()
        } else {
            view.processDelegate = context.coordinator
        }
        // Mouse reporting stays on (SwiftTerm's default): programs
        // that ask for the mouse, like Claude Code's own transcript
        // scrolling and pagers, get it, and Shift bypasses to local
        // selection and scrolling. Programs that leave the mouse
        // alone scroll and select natively without any modifier.
        view.font = CodeStyle.nsFont
        view.reflowsCopies = reflowsCopies
        context.coordinator.installBlockSelection(on: view)
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(transport, in: view)
        return view
    }

    /// Re-themes when the appearance actually changes; the start
    /// also retries here as a fallback and reattaches when SwiftUI
    /// reused the view for a different command.
    func updateNSView(_ view: PaneTerminalView, context: Context) {
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(transport, in: view)
        context.coordinator.updateFocus(isActive: isActive, of: view)
        if case .shell = transport, isActive {
            context.coordinator.clearIfRequested(clearRequest, in: view)
        }
    }

    /// Creates the control mode coordinator.
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
