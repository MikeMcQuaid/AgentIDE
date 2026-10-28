import SanductorDomain
import SwiftUI

/// A remembered disclosure shared by both status sidebars.
public struct SidebarStatusGroup<Content: View>: View {
    // MARK: Lifecycle

    public init(status: SidebarStatus, count: Int, @ViewBuilder content: () -> Content) {
        self.status = status
        self.count = count
        self.content = content()
        _collapsed = AppStorage(wrappedValue: false, "collapsedSidebarStatus." + status.rawValue)
    }

    // MARK: Public

    public var body: some View {
        Button {
            withAnimation(Motion.quick) { collapsed.toggle() }
        } label: {
            HStack(spacing: spacing) {
                Image(systemName: "chevron.right")
                    .interfaceFont(.caption, weight: .semibold)
                    .rotationEffect(.degrees(collapsed ? 0 : expandedDegrees))
                    .accessibilityHidden(true)
                Text(status.rawValue).interfaceFont(.headline)
                Text("(" + String(count) + ")")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, padding)
            #if os(iOS)
                .frame(minHeight: minimumTouchSize)
            #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .help((collapsed ? "Expand " : "Collapse ") + status.rawValue)
        if collapsed == false {
            content
        }
    }

    // MARK: Private

    @AppStorage private var collapsed: Bool

    private let spacing: CGFloat = 6

    private let padding: CGFloat = 4

    private let expandedDegrees: Double = 90

    private let minimumTouchSize: CGFloat = 44

    private let status: SidebarStatus
    private let count: Int
    private let content: Content
}
