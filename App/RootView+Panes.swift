import AgentIDEDomain
import SwiftUI

// MARK: - Shell layers

/// The shell tab's layers, split from the view for length.
extension RootView {
    /// Every running shell, not just the selected worktree's: a shell
    /// dies with its pane, and switching worktrees or opening a page
    /// is not destroying a worktree. Only the selected worktree's
    /// shell shows and takes keys. The close button hard-terminates
    /// shells that cannot Ctrl-D out.
    @ViewBuilder
    func shellLayers(for item: WorktreeItem) -> some View {
        let path = item.worktree.path
        ForEach(runningShellPaths, id: \.self) { shellPath in
            let isShown = shellPath == path
            // The closure stays a non-final argument: the formatter
            // rewrites a trailing one after a multiline call.
            shellTerminal(
                at: shellPath,
                onExit: { closeShell(at: shellPath) },
                isActive: isShown && utilityTab == .shell && isCovered == false,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
        }
        if hasRunningShell(at: path) == false {
            StartShellButton { startShell(at: path) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
