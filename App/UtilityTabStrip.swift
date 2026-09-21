import SwiftUI
import TerminalUI

/// The toolbar's utility tab bubbles: plain buttons rather than a
/// segmented picker, because toolbars reposition segmented controls
/// unpredictably and buttons carry their own tooltips.
struct UtilityTabStrip: View {
    // MARK: Internal

    let onOpenShell: () -> Void
    let onCloseShells: (() -> Void)?

    var body: some View {
        ForEach(UtilityTab.allCases, id: \.self) { tab in
            button(tab)
        }
        .onChange(of: utilityTab, initial: true) {
            if UtilityTab(rawValue: utilityTab) == nil {
                utilityTab = UtilityTab.review.rawValue
            }
        }
    }

    // MARK: Private

    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = UtilityTab.review.rawValue

    @State private var hovered: String?

    private var errorLog: ErrorLog = .shared

    private var tabStyle: TabStyle = .init()

    @ViewBuilder private var shellControls: some View {
        Button {
            utilityTab = UtilityTab.shell.rawValue
            onOpenShell()
        } label: {
            Image(systemName: "plus")
                .font(tabStyle.font)
                .accessibilityLabel("New shell")
                .padding(.horizontal, TabCapsule.horizontalPadding)
                .padding(.vertical, TabCapsule.verticalPadding)
                .contentShape(Rectangle())
        }
        .hoverHelp("Open another shell in this worktree", shortcut: "⇧⌘T")
        if let onCloseShells, utilityTab == UtilityTab.shell.rawValue {
            Button(action: onCloseShells) {
                Image(systemName: "xmark")
                    .font(tabStyle.badge)
                    .accessibilityLabel("Close all shells")
                    .padding(.trailing, TabCapsule.horizontalPadding)
                    .padding(.vertical, TabCapsule.verticalPadding)
                    .contentShape(Rectangle())
            }
            .hoverHelp("End all shells and their processes in this worktree immediately")
        }
    }

    private func button(_ tab: UtilityTab) -> some View {
        HStack(spacing: 0) {
            Button {
                utilityTab = tab.rawValue
            } label: {
                HStack(spacing: TabCapsule.contentSpacing) {
                    Text(tab.title)
                        .font(tabStyle.font)
                    if tab == .errors, errorLog.unreadErrorCount > 0 {
                        Text(String(errorLog.unreadErrorCount))
                            .font(tabStyle.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TabCapsule.contentSpacing)
                            .background(Capsule().fill(.red))
                    }
                }
                .padding(.leading, TabCapsule.horizontalPadding)
                .padding(.trailing, tab == .shell ? 0 : TabCapsule.horizontalPadding)
                .padding(.vertical, TabCapsule.verticalPadding)
                .contentShape(Rectangle())
            }
            // Numbered from the full list to match the View menu.
            .hoverHelp(tab.help, shortcut: "⌘" + String((UtilityTab.allCases.firstIndex(of: tab) ?? 0) + 1))
            if tab == .shell {
                shellControls
            }
        }
        .buttonStyle(.plain)
        .tabCapsule(isSelected: tab.rawValue == utilityTab, isHovered: hovered == tab.rawValue)
        .onHover { inside in
            hovered = inside ? tab.rawValue : (hovered == tab.rawValue ? nil : hovered)
        }
    }
}
