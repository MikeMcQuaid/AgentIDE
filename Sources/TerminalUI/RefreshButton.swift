import SwiftUI

/// The one refresh control: an icon-only button that disables
/// itself while its async action runs.
public struct RefreshButton: View {
    // MARK: Lifecycle

    /// Creates the button around an async refresh action.
    @preconcurrency
    public init(action: @escaping @MainActor () async -> Void) {
        self.action = action
    }

    // MARK: Public

    public var body: some View {
        Button {
            guard isBusy == false else {
                return
            }

            isBusy = true
            Task {
                await action()
                isBusy = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .accessibilityLabel("Refresh")
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
    }

    // MARK: Private

    @State private var isBusy = false

    private let action: @MainActor () async -> Void
}
