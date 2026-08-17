import SwiftUI
import TerminalUI

/// The toolbar's utility tab bubbles: plain buttons rather than a
/// segmented picker, because toolbars reposition segmented controls
/// unpredictably and buttons carry their own tooltips.
struct UtilityTabStrip: View {
    // MARK: Internal

    var body: some View {
        // The errors tab hides until the first failure of the
        // session, then sticks around even across a clear.
        ForEach(UtilityTab.allCases, id: \.self) { tab in
            button(tab)
        }
    }

    // MARK: Private

    private static let horizontalPadding: CGFloat = 8
    private static let badgeSpacing: CGFloat = 4
    private static let verticalPadding: CGFloat = 3
    private static let selectedOpacity = 0.25
    private static let hoverOpacity = 0.08

    @AppStorage("utilityTab")
    private var utilityTab = UtilityTab.review.rawValue

    @State private var hovered: String?

    private var errorLog: ErrorLog = .shared

    private func button(_ tab: UtilityTab) -> some View {
        Button {
            utilityTab = tab.rawValue
        } label: {
            HStack(spacing: Self.badgeSpacing) {
                Text(tab.title)
                    .font(.callout)
                if tab == .errors, errorLog.errorCount > 0 {
                    Text(String(errorLog.errorCount))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Self.badgeSpacing)
                        .background(Capsule().fill(.red))
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(
                Capsule().fill(
                    tab.rawValue == utilityTab
                        ? Color.accentColor.opacity(Self.selectedOpacity)
                        : hovered == tab.rawValue
                        ? Color.primary.opacity(Self.hoverOpacity)
                        : Color.clear,
                ),
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? tab.rawValue : (hovered == tab.rawValue ? nil : hovered)
        }
        .hoverHelp(tab.help)
    }
}
