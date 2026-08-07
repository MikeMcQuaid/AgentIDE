import SwiftUI

/// The all-agents dashboard, an empty placeholder until worktrees and
/// sessions exist.
public struct DashboardView: View {
    // MARK: Lifecycle

    /// Creates the dashboard view.
    public init() {
        // SwiftUI requires a public initialiser across module boundaries.
    }

    // MARK: Public

    /// The placeholder content shown while no agents exist.
    public var body: some View {
        ContentUnavailableView(
            "No agents yet",
            systemImage: "rectangle.stack",
            description: Text("Worktrees and their agents will appear here, grouped by repository."),
        )
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
    }

    // MARK: Private

    private static let minimumWidth: CGFloat = 480
    private static let minimumHeight: CGFloat = 320
}
