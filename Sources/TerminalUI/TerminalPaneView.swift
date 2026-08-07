import SwiftUI

/// The shared terminal surface, a placeholder until the core loop
/// slice.
public struct TerminalPaneView: View {
    // MARK: Lifecycle

    /// Creates the terminal pane view.
    public init() {
        // SwiftUI requires a public initialiser across module boundaries.
    }

    // MARK: Public

    /// The placeholder content.
    public var body: some View {
        Text("The terminal arrives with the core loop slice.")
    }
}
