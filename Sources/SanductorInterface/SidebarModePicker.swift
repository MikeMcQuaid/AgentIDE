import SanductorDomain
import SwiftUI

/// The sidebar uses the same compact segmented control as PR scopes.
public struct SidebarModePicker: View {
    // MARK: Lifecycle

    public init(mode: Binding<SidebarMode>) {
        _mode = mode
    }

    // MARK: Public

    public var body: some View {
        Picker("Group by", selection: $mode) {
            ForEach(SidebarMode.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .help("Group work by repository or status")
        #if os(macOS)
            .background(
                Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Self.cornerRadius),
            )
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: Self.borderWidth)
                .allowsHitTesting(false))
        #else
                .background(.background.opacity(Self.backgroundOpacity), in: Capsule())
        #endif
                .padding(Self.padding)
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let cornerRadius: CGFloat = 5
    private static let borderWidth: CGFloat = 0.5
    private static let backgroundOpacity = 0.8

    @Binding private var mode: SidebarMode
}
