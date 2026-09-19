import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - Shells

/// The utility pane's shells: which are open where, which one each
/// worktree is showing, and the layers that keep every one of them
/// running behind whatever is on screen.
extension RootView {
    /// Whether a worktree has a shell, or needs the start button.
    func hasRunningShell(at path: String) -> Bool {
        shellTabs.shells(in: path).isEmpty == false
    }

    /// Starts another shell in a worktree by mounting its pane, and
    /// shows it: one worktree runs as many as the work needs, a
    /// server holding one while git and API calls use the next.
    func startShell(at path: String) {
        shellTabs.open(in: path)
    }

    /// Shows one of the worktree's shells, leaving the rest running
    /// behind it.
    func selectShell(_ identifier: ShellTabs.Shell.ID) {
        shellTabs.select(identifier)
    }

    /// Ends a shell instantly: unmounting the pane kills its PTY,
    /// even when the shell has wedged beyond Ctrl-D.
    func closeShell(_ identifier: ShellTabs.Shell.ID) {
        shellTabs.close(identifier)
    }

    /// Every running shell, not just the selected worktree's and not
    /// just the one it is showing: a shell dies with its pane, and
    /// switching worktrees, tabs or shells is not destroying a
    /// worktree. Only the shell the selected worktree points at
    /// shows and takes keys. Its tab's close button hard-terminates
    /// shells that cannot Ctrl-D out.
    func shellLayers(for item: WorktreeItem?) -> some View {
        let path = item?.worktree.path
        let shown = path.flatMap { shellTabs.selected(in: $0) }
        return ZStack {
            ForEach(shellTabs.all) { shell in
                let isShown = shell.id == shown
                shellTerminal(
                    at: shell.worktreePath,
                    onExit: { closeShell(shell.id) },
                    isActive: isShown && showsUtility && utilityTab == .shell && isCovered == false,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Each worktree reserves its own row, so switching
                // worktrees never resizes the hidden terminals.
                .padding(.top, shellTabs.shells(in: shell.worktreePath).count > 1 ? Self.toggleRowHeight : 0)
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
            }
            if let path, hasRunningShell(at: path) == false {
                StartShellButton { startShell(at: path) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) { shellStrip(for: path) }
    }

    /// A full-width tab bar only when there is a choice of shells.
    @ViewBuilder
    func shellStrip(for path: String?) -> some View {
        let shells = path.map { shellTabs.shells(in: $0) } ?? []
        if let path, shells.count > 1 {
            ShellTabStrip(
                shells: shells,
                selected: shellTabs.selected(in: path),
                onSelect: { selectShell($0) },
                onClose: { closeShell($0) },
            )
            .frame(height: Self.toggleRowHeight)
        }
    }
}

// MARK: - StartShellButton

/// The shell tab's empty state: one button that starts the shell.
private struct StartShellButton: View {
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            Label("Start shell", systemImage: "terminal")
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .hoverHelp("Open a host-user shell here; it runs until you close it or the app quits")
    }

    // MARK: Private
}
