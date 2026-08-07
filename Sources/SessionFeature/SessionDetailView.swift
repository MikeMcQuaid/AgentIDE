import SwiftUI

/// A single agent session's detail, a placeholder until the core loop
/// slice.
public struct SessionDetailView: View {
    // MARK: Lifecycle

    /// Creates the session detail view.
    public init() {
        // SwiftUI requires a public initialiser across module boundaries.
    }

    // MARK: Public

    /// The placeholder content.
    public var body: some View {
        Text("Session detail arrives with the core loop slice.")
    }
}
