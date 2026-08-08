import SwiftTerm
import SwiftUI

/// An embedded terminal running an argv on a local PTY. Closing the
/// view only disconnects this client; tmux sessions keep running in
/// the sandbox.
public struct TerminalPaneView: NSViewRepresentable {
    // MARK: Lifecycle

    /// Creates a terminal that runs an argv; the argv itself decides
    /// its working directory.
    public init(command: [String]) {
        self.command = command
    }

    // MARK: Public

    /// Builds the SwiftTerm view and starts the process.
    public func makeNSView(context _: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        let resolved = command.first?.hasPrefix("/") == true ? command : ["/usr/bin/env"] + command
        view.startProcess(
            executable: resolved.first ?? "/bin/zsh",
            args: Array(resolved.dropFirst()),
            environment: nil,
            execName: nil,
        )
        return view
    }

    /// The terminal owns its state; nothing to update.
    public func updateNSView(_: LocalProcessTerminalView, context _: Context) {
        // SwiftTerm manages the PTY after launch.
    }

    // MARK: Private

    private let command: [String]
}
