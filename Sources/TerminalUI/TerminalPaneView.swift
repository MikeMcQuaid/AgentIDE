import SwiftTerm
import SwiftUI

// MARK: - TerminalPaneView

/// An embedded terminal attached to a tmux session as a control mode
/// client: tmux streams pane output as protocol events and the view
/// renders them locally, so selection, copying, wheel scrolling and
/// scrollback are all native. Closing the view only detaches this
/// client; the tmux session keeps running.
public struct TerminalPaneView: View {
    // MARK: Lifecycle

    /// Creates a terminal that spawns a `tmux -C` argv and renders
    /// the attached session. `reflowsCopies` reflows multi-line
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
        self.command = command
        self.reflowsCopies = reflowsCopies
        self.isActive = isActive
        self.onProcessTerminated = onProcessTerminated
    }

    // MARK: Public

    public var body: some View {
        TerminalRepresentable(
            command: command,
            reflowsCopies: reflowsCopies,
            isActive: isActive,
            onProcessTerminated: onProcessTerminated,
        )
    }

    // MARK: Private

    private let command: [String]
    private let reflowsCopies: Bool
    private let isActive: Bool
    private let onProcessTerminated: (@MainActor () -> Void)?
}

// MARK: - TerminalRepresentable

/// Bridges the SwiftTerm view into SwiftUI and owns the control
/// mode client.
struct TerminalRepresentable: NSViewRepresentable {
    // MARK: Internal

    let command: [String]
    let reflowsCopies: Bool
    let isActive: Bool
    let onProcessTerminated: (@MainActor () -> Void)?

    /// Detaches the coordinator's client with the view.
    static func dismantleNSView(_: PaneTerminalView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// Builds the SwiftTerm view and themes it; the client attaches
    /// as soon as layout gives the view its real size. Mouse
    /// reporting stays off so dragging always selects locally and
    /// the wheel always scrolls the local scrollback.
    func makeNSView(context: Context) -> PaneTerminalView {
        let view = PaneTerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.allowMouseReporting = false
        view.font = CodeStyle.nsFont
        view.reflowsCopies = reflowsCopies
        context.coordinator.installBlockSelection(on: view)
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
        return view
    }

    /// Re-themes when the appearance actually changes; the start
    /// also retries here as a fallback and reattaches when SwiftUI
    /// reused the view for a different command.
    func updateNSView(_ view: PaneTerminalView, context: Context) {
        applyTheme(to: view, context: context)
        context.coordinator.startWhenSized(command, in: view)
        context.coordinator.updateFocus(isActive: isActive, of: view)
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
