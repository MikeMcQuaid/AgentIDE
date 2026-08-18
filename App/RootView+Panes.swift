import AgentIDEDomain
import SessionFeature
import SwiftUI

// MARK: - Shell layers

/// The shell tab's layers, split from the view for length.
extension RootView {
    /// A running shell stays mounted whichever tab, worktree or page
    /// shows, so its terminal survives everything short of destroying
    /// the worktree it runs in. Both layers always fill the pane, so
    /// switches never resize a hidden terminal; a resize would make
    /// the shell reprint its prompt, which reads as stray newlines.
    /// Shells start only from their button, and a quit shell (Ctrl-D)
    /// returns to it.
    func utilityContent(for item: WorktreeItem) -> some View {
        let showsShell = utilityTab == .shell
        let showsBrowser = utilityTab == .browser
        let path = item.worktree.path
        return ZStack {
            shellLayers(for: item)
                .opacity(showsShell ? 1 : 0)
                .allowsHitTesting(showsShell)
            if showsShell == false, showsBrowser == false {
                // Identity keyed by worktree, so switching in the
                // sidebar always rebuilds the pane's state. The
                // backgrounds must not expand into the ignored
                // titlebar safe area, where they would paint over
                // the tab header above.
                switchedUtility(for: item, conversationPath: conversationWorktree)
                    .id("utility-" + path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.background, ignoresSafeAreaEdges: [])
            }
            // Like the shells, every browser opened so far stays
            // mounted, so a page survives tab and worktree switches
            // without reloading; only this worktree's is shown.
            browserLayers(for: item)
                .opacity(showsBrowser ? 1 : 0)
                .allowsHitTesting(showsBrowser)
        }
        .task(id: item.id + utilityTabName) {
            if utilityTab == .browser {
                visitBrowser(at: path)
            }
        }
    }

    /// Every browser page opened so far, kept loaded whichever
    /// worktree is being worked in: the session manager lists what
    /// they cost and closes the ones that are not worth it.
    @ViewBuilder
    func browserLayers(for item: WorktreeItem) -> some View {
        let path = item.worktree.path
        ForEach(visitedBrowserPaths, id: \.self) { browserPath in
            let isShown = browserPath == path
            BrowserView(worktreePath: browserPath, isActive: isShown && utilityTab == .browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background, ignoresSafeAreaEdges: [])
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
        }
    }

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
