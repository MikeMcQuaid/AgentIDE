import SwiftUI
import TerminalUI

/// The toolbar's utility tab bubbles: plain buttons rather than a
/// segmented picker, because toolbars reposition segmented controls
/// unpredictably and buttons carry their own tooltips.
struct UtilityTabStrip: View {
    // MARK: Internal

    var body: some View {
        ForEach(UtilityTab.allCases, id: \.self) { tab in
            button(tab)
        }
    }

    // MARK: Private

    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = UtilityTab.review.rawValue

    @State private var hovered: String?

    private var errorLog: ErrorLog = .shared

    private var tabStyle: TabStyle = .init()

    private func button(_ tab: UtilityTab) -> some View {
        Button {
            utilityTab = tab.rawValue
        } label: {
            HStack(spacing: TabCapsule.contentSpacing) {
                Text(tab.title)
                    .font(tabStyle.font)
                if tab == .errors, errorLog.errorCount > 0 {
                    Text(String(errorLog.errorCount))
                        .font(tabStyle.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TabCapsule.contentSpacing)
                        .background(Capsule().fill(.red))
                }
            }
            .padding(.horizontal, TabCapsule.horizontalPadding)
            .padding(.vertical, TabCapsule.verticalPadding)
            .tabCapsule(isSelected: tab.rawValue == utilityTab, isHovered: hovered == tab.rawValue)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? tab.rawValue : (hovered == tab.rawValue ? nil : hovered)
        }
        // Numbered from the full tab list, so the tooltip always
        // matches the View menu's own shortcut.
        .hoverHelp(tab.help, shortcut: "⌘" + String((UtilityTab.allCases.firstIndex(of: tab) ?? 0) + 1))
    }
}
