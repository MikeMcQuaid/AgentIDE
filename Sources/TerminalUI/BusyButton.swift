import SwiftUI

/// A button for actions that must not run twice: a tap disables it
/// and swaps the label to its present-tense form instantly, staying
/// that way until the async action finishes. Every button whose
/// action is slow or dangerous to double-press should be one.
public struct BusyButton: View {
    // MARK: Lifecycle

    /// Creates the button; `busy` is the label shown while the
    /// action runs, such as Fixing for Fix. With `systemImage` the
    /// icon leads and an empty title is fine. `prominent` marks a
    /// surface's one primary action.
    @preconcurrency
    public init(
        _ title: String,
        busy: String,
        systemImage: String? = nil,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping @MainActor () async -> Void,
    ) {
        self.title = title
        busyTitle = busy
        self.systemImage = systemImage
        isProminent = prominent
        isDisabled = disabled
        self.action = action
    }

    // MARK: Public

    public var body: some View {
        if isProminent {
            core.buttonStyle(.glassProminent)
        } else {
            core.buttonStyle(.glass)
        }
    }

    // MARK: Private

    private static let iconSpacing: CGFloat = 3

    @State private var isBusy = false

    private let title: String
    private let busyTitle: String
    private let systemImage: String?
    private let isProminent: Bool
    private let isDisabled: Bool
    private let action: @MainActor () async -> Void

    private var core: some View {
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
            HStack(spacing: Self.iconSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityLabel(isBusy ? busyTitle : title)
                }
                if isBusy || title.isEmpty == false {
                    Text(isBusy ? busyTitle : title)
                }
            }
        }
        .disabled(isDisabled || isBusy)
    }
}
