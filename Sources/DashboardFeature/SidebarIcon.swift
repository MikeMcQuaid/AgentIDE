import SwiftUI
import TerminalUI

/// Sidebar icons share a highlight on hover and keyboard focus.
struct SidebarIcon: View {
    // MARK: Internal

    let systemName: String
    let verticalPadding: CGFloat
    var rotation: Angle = .zero

    var body: some View {
        Image(systemName: systemName)
            .accessibilityHidden(true)
            .interfaceFont(.caption, weight: .semibold)
            .rotationEffect(rotation)
            .animation(Motion.quick, value: rotation)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Color(nsColor: .labelColor).opacity(isHovered || isFocused ? Self.highlightOpacity : 0)),
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(Motion.quick, value: isHovered || isFocused)
    }

    // MARK: Private

    private static let horizontalPadding: CGFloat = 4
    private static let cornerRadius: CGFloat = 5
    private static let highlightOpacity = 0.08

    @Environment(\.isFocused)
    private var isFocused

    @State private var isHovered = false
}
