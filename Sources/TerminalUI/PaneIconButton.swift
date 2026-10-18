import SwiftUI

/// A compact pane control whose selected state fills its bubble.
public struct PaneIconButton: View {
    // MARK: Lifecycle

    public init(
        _ systemImage: String,
        help: String,
        isOn: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void,
    ) {
        self.systemImage = systemImage
        self.help = help
        self.isOn = isOn
        self.disabled = disabled
        self.action = action
    }

    // MARK: Public

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .interfaceFont(.body)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(Self.iconPadding)
                .background(
                    RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                        .fill(isOn ? Color.accentColor.opacity(Self.iconSelectedOpacity) : .clear),
                )
                .contentShape(Rectangle())
                .accessibilityLabel(help)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Self.disabledOpacity : 1)
        // The colour fill alone is invisible to VoiceOver.
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .hoverHelp(help)
    }

    // MARK: Private

    private static let iconPadding: CGFloat = 4
    private static let iconCornerRadius: CGFloat = 5
    private static let iconSelectedOpacity = 0.2
    private static let disabledOpacity = 0.4

    private let systemImage: String
    private let help: String
    private let isOn: Bool
    private let disabled: Bool
    private let action: () -> Void

    private var interfaceStyle: InterfaceStyle = .init()

    private var iconSize: CGFloat {
        interfaceStyle.appKitFont(.body).pointSize + 1
    }
}
