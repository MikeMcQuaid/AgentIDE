import SwiftUI

/// The same active-loop indicator in toolbars and sidebar rows.
public struct FeedbackLoopIcon: View {
    // MARK: Lifecycle

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    // MARK: Public

    public var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .accessibilityLabel("Autofix feedback loop")
            .symbolEffect(.rotate, options: .repeating, isActive: isRunning && reducesMotion == false)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion)
    private var reducesMotion

    private let isRunning: Bool
}
