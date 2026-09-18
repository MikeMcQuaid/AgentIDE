import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The shell tab's own strip, under the utility tabs it matches: one
/// capsule per shell running in this worktree, each closing itself,
/// and a plus that opens another. A worktree with no shell shows no
/// strip, only the row it would fill, so opening the first one never
/// resizes the shells the other worktrees are holding.
struct ShellTabStrip: View {
    // MARK: Internal

    let shells: [ShellTabs.Shell]
    let selected: ShellTabs.Shell.ID?
    let onSelect: (ShellTabs.Shell.ID) -> Void
    let onClose: (ShellTabs.Shell.ID) -> Void
    let onOpen: () -> Void

    var body: some View {
        // The strip scrolls rather than squeezing: a narrow pane
        // holding several shells keeps every capsule readable.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TabCapsule.contentSpacing) {
                ForEach(shells) { shell in
                    capsule(for: shell)
                }
                openButton
            }
            // A capsule opening or closing slides the ones after it;
            // the terminals below never move, since the row keeps
            // its height whatever the strip holds.
            .animation(Motion.quick, value: shells.map(\.id))
        }
    }

    // MARK: Private

    /// The plus shares the strip's hover state; no shell can hold
    /// this identity, since identities are handed out from one.
    private static let openIdentity = 0

    @State private var hovered: ShellTabs.Shell.ID?

    private var tabStyle: TabStyle = .init()

    private var openButton: some View {
        Button(action: onOpen) {
            Image(systemName: "plus")
                .font(tabStyle.font)
                .accessibilityLabel("New shell")
                .padding(.horizontal, TabCapsule.horizontalPadding)
                .padding(.vertical, TabCapsule.verticalPadding)
                .tabCapsule(isSelected: false, isHovered: hovered == Self.openIdentity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? Self.openIdentity : (hovered == Self.openIdentity ? nil : hovered)
        }
        .hoverHelp("Open another shell in this worktree", shortcut: "⇧⌘T")
    }

    /// The name and its close, filling the capsule between them, so
    /// every point of it does what the part under the pointer says.
    private func capsule(for shell: ShellTabs.Shell) -> some View {
        HStack(spacing: 0) {
            Button {
                onSelect(shell.id)
            } label: {
                Text(shell.title)
                    .font(tabStyle.font)
                    .padding(.leading, TabCapsule.horizontalPadding)
                    .padding(.trailing, TabCapsule.contentSpacing)
                    .padding(.vertical, TabCapsule.verticalPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("Show this shell in the pane")
            Button {
                onClose(shell.id)
            } label: {
                Image(systemName: "xmark")
                    .font(tabStyle.badge)
                    .accessibilityLabel("Close " + shell.title)
                    .padding(.trailing, TabCapsule.horizontalPadding)
                    .padding(.vertical, TabCapsule.verticalPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHelp("End this shell and its process immediately")
        }
        .tabCapsule(isSelected: shell.id == selected, isHovered: hovered == shell.id)
        .onHover { inside in
            hovered = inside ? shell.id : (hovered == shell.id ? nil : hovered)
        }
    }
}
