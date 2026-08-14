import SwiftUI

/// A button for actions that must not run twice: a tap disables it
/// and swaps the label to its present-tense form instantly, staying
/// that way until the async action finishes. Every button whose
/// action is slow or dangerous to double-press should be one.
public struct BusyButton: View {
    // MARK: Lifecycle

    /// Creates the button; `busy` is the label shown while the
    /// action runs, such as Fixing for Fix.
    @preconcurrency
    public init(
        _ title: String,
        busy: String,
        disabled: Bool = false,
        action: @escaping @MainActor () async -> Void,
    ) {
        self.title = title
        busyTitle = busy
        isDisabled = disabled
        self.action = action
    }

    // MARK: Public

    public var body: some View {
        Button(isBusy ? busyTitle : title) {
            guard isBusy == false else {
                return
            }

            isBusy = true
            Task {
                await action()
                isBusy = false
            }
        }
        .disabled(isDisabled || isBusy)
    }

    // MARK: Private

    @State private var isBusy = false

    private let title: String
    private let busyTitle: String
    private let isDisabled: Bool
    private let action: @MainActor () async -> Void
}
