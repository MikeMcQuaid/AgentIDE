import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Full-width tabs for a worktree with multiple shells.
struct ShellTabStrip: View {
    // MARK: Internal

    let shells: [ShellTabs.Shell]
    let selected: ShellTabs.Shell.ID?
    let onSelect: (ShellTabs.Shell.ID) -> Void
    let onClose: (ShellTabs.Shell.ID) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(shells) { shell in
                            tab(for: shell)
                                .frame(minWidth: geometry.size.width / CGFloat(max(shells.count, 1)))
                                .id(shell.id)
                        }
                    }
                    .frame(height: geometry.size.height)
                }
                .onChange(of: selected, initial: true) {
                    if let selected {
                        proxy.scrollTo(selected)
                    }
                }
            }
        }
        .background(.bar, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Private

    @State private var hovered: ShellTabs.Shell.ID?

    private var tabStyle: TabStyle = .init()

    private func tab(for shell: ShellTabs.Shell) -> some View {
        HStack(spacing: 0) {
            Button {
                onSelect(shell.id)
            } label: {
                Text(shell.title)
                    .font(tabStyle.font)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, TabCapsule.horizontalPadding)
                    .padding(.trailing, TabCapsule.contentSpacing)
                    .padding(.vertical, TabCapsule.verticalPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(shell.id == selected ? .isSelected : [])
            .hoverHelp("Show this shell in the pane")
            Button {
                onClose(shell.id)
            } label: {
                Image(systemName: "xmark")
                    .font(tabStyle.badge)
                    .accessibilityLabel("Close " + shell.title)
                    .padding(.leading, TabCapsule.contentSpacing)
                    .padding(.trailing, TabCapsule.horizontalPadding)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("End this shell and its process immediately")
        }
        .background(TabCapsule.fill(isSelected: shell.id == selected, isHovered: hovered == shell.id))
        .overlay(alignment: .trailing) { Divider() }
        .onHover { inside in
            hovered = inside ? shell.id : (hovered == shell.id ? nil : hovered)
        }
    }
}
