import SwiftUI
import TerminalUI

/// The toolbar's utility tab bubbles: plain buttons rather than a
/// segmented picker, because toolbars reposition segmented controls
/// unpredictably and buttons carry their own tooltips.
struct UtilityTabStrip: View {
    // MARK: Internal

    var body: some View {
        ForEach(Array(UtilityTab.allCases.enumerated()), id: \.element) { index, tab in
            button(tab, at: index)
        }
    }

    // MARK: Private

    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 3
    private static let selectedOpacity = 0.25

    @AppStorage("utilityTabIndex")
    private var utilityTabIndex = 0

    private func button(_ tab: UtilityTab, at index: Int) -> some View {
        Button {
            utilityTabIndex = index
        } label: {
            Text(tab.title)
                .font(.callout)
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .background(
                    Capsule().fill(
                        index == utilityTabIndex
                            ? Color.accentColor.opacity(Self.selectedOpacity)
                            : Color.clear,
                    ),
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverHelp(tab.help)
    }
}
