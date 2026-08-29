import SwiftUI

/// A button for actions that must not run twice: a tap disables it
/// and swaps the label to its present-tense form instantly, staying
/// that way until the async action finishes. Every button whose
/// action is slow or dangerous to double-press should be one.
public struct BusyButton: View {
    // MARK: Lifecycle

    /// Creates the button; `busy` is the label shown while the
    /// action runs, such as Fixing for Fix. `keepsTitle` holds the
    /// label still and only dims, for surfaces whose status line
    /// already narrates the work. With `systemImage` the
    /// icon leads and an empty title is fine, but VoiceOver then
    /// needs `accessibilityLabel`. `prominent` marks a surface's one
    /// primary action.
    @preconcurrency
    public init(
        _ title: String,
        busy: String,
        systemImage: String? = nil,
        accessibilityLabel: String? = nil,
        prominent: Bool = false,
        disabled: Bool = false,
        keepsTitle: Bool = false,
        action: @escaping @MainActor () async -> Void,
    ) {
        self.title = title
        busyTitle = keepsTitle ? title : busy
        self.systemImage = systemImage
        spokenLabel = accessibilityLabel
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

    /// The icon's and the spinner's shared frame, so swapping one
    /// for the other moves nothing.
    private static let iconSlot: CGFloat = 14

    @State private var isBusy = false

    private let title: String
    private let busyTitle: String
    private let systemImage: String?
    private let spokenLabel: String?
    private let isProminent: Bool
    private let isDisabled: Bool
    private let action: @MainActor () async -> Void

    /// What VoiceOver reads: the visible label when there is one,
    /// the explicit spoken label for icon-only buttons.
    private var spokenTitle: String {
        let visible = isBusy ? busyTitle : title
        return visible.isEmpty ? spokenLabel ?? "" : visible
    }

    private var core: some View {
        Button {
            guard isBusy == false else {
                return
            }

            isBusy = true
            // Explicitly main-actor: the continuation after the
            // await must not write view state from elsewhere.
            Task { @MainActor in
                await action()
                isBusy = false
            }
        } label: {
            // Both states render and the hidden one keeps its size,
            // so a press never resizes the button and the row never
            // shuffles; while busy a spinner takes the icon's slot.
            ZStack {
                stateLabel(text: title, spinning: false)
                    .opacity(isBusy ? 0 : 1)
                stateLabel(text: busyTitle, spinning: true)
                    .opacity(isBusy ? 1 : 0)
            }
            .animation(Motion.quick, value: isBusy)
        }
        .accessibilityLabel(spokenTitle)
        .disabled(isDisabled || isBusy)
    }

    /// One state's content: the icon or the progress spinner in the
    /// same fixed slot, then the state's text.
    private func stateLabel(text: String, spinning: Bool) -> some View {
        HStack(spacing: Self.iconSpacing) {
            if spinning {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: Self.iconSlot, height: Self.iconSlot)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: Self.iconSlot, height: Self.iconSlot)
                    .accessibilityLabel(spokenTitle)
            }
            if text.isEmpty == false {
                Text(text)
            }
        }
    }
}
