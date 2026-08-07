import SwiftUI

/// The diff review surface, a placeholder until the review slice.
public struct ReviewView: View {
    // MARK: Lifecycle

    /// Creates the review view.
    public init() {
        // SwiftUI requires a public initialiser across module boundaries.
    }

    // MARK: Public

    /// The placeholder content.
    public var body: some View {
        Text("Diff review arrives with the review slice.")
    }
}
