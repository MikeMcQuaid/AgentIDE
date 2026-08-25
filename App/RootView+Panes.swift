import AgentIDEDomain
import DashboardFeature
import SessionFeature
import SwiftUI
import TerminalUI

// MARK: - Shell layers

/// The shell tab's layers, split from the view for length.
extension RootView {
    /// One conversations UI everywhere: a live session shows its
    /// terminal; anything else shows the conversation list, scoped
    /// to the worktree or covering the whole repository on its page;
    /// a worktree with nothing to list offers the new session form.
    @ViewBuilder
    func primary(for item: WorktreeItem) -> some View {
        if item.worktree.isHostDirectory {
            // The editor takes the pane an agent would have, and
            // leaves the utility pane, so it is one editor with one
            // set of shortcuts wherever it shows.
            editorPane(for: item)
        } else if item.isPlaceholder {
            // The row exists before the worktree does.
            LaunchProgressView(
                "Creating the worktree and starting the agent…",
                progress: dependencies.dashboard.launchProgress,
            )
        } else if resumingWorktree == item.worktree.path {
            // Before the terminal: a finished session's pane is what
            // the resume kills, and a terminal left attached to it
            // reported the pane gone.
            LaunchProgressView("Resuming the conversation…", progress: dependencies.dashboard.launchProgress)
        } else if dependencies.dashboard.isAwaitingSession(item) {
            // The row had an agent when the app last looked and
            // herdr has not answered yet: waiting is honest, where
            // the conversations page would claim the session ended.
            LaunchProgressView("Attaching to the agent…", waitingOn: "herdr to answer")
        } else if let session = item.session {
            agentTerminal(for: session, at: item.worktree.path, isActive: isCovered == false)
                .id(session.name)
                // Dropped files stage into the shared workspace (the
                // sandbox cannot read host paths) and their staged
                // paths type into the agent.
                .dropDestination(for: URL.self) { urls, _ in
                    dropFiles(urls, into: session.name)
                }
        } else if item.worktree.path == item.worktree.repositoryPath, startingSession != item.worktree.path {
            repositoryConversations(for: item)
        } else if item.pastSessions.isEmpty == false, startingSession != item.worktree.path {
            worktreeConversations(for: item)
        } else {
            CreateSessionPane(
                worktree: item.worktree,
                model: dependencies.dashboard,
                canResume: dependencies.service.hasRecordedSession(worktreePath: item.worktree.path),
                // Only a worktree with conversations to go back to
                // shows the way back.
                onShowConversations: item.pastSessions.isEmpty
                    && item.worktree.path != item.worktree.repositoryPath ? nil : { startingSession = nil },
                onResume: { await resumeLatest(in: item) },
                onStarted: { await sessionStarted(in: item.worktree.path) },
            )
        }
    }

    /// The primary column: the session strip over whichever pane
    /// the worktree calls for. A covering page hides it rather than
    /// unmounting it, so the agent's terminal keeps its herdr client
    /// and its scrollback, and the utility toggle parks at its top
    /// right while the utility pane is hidden, in exactly the spot
    /// that pane's header shows it, so it never moves on toggle.
    func primaryColumn(for item: WorktreeItem) -> some View {
        VStack(spacing: 0) {
            sessionStrip(for: item)
            primary(for: item)
        }
        .opacity(isCovered ? 0 : 1)
        .allowsHitTesting(isCovered == false)
        .overlay { coveringPage }
        .overlay(alignment: .topTrailing) {
            if showsUtility == false {
                utilityToggleButton
                    .frame(height: Self.toggleRowHeight)
                    .padding(.trailing, Self.stripSpacing)
            }
        }
        .frame(
            minWidth: PaneLayout.primaryMinimum,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top,
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Narrows the sidebar to the least its rows need and splits
    /// what is left evenly between the panes that do the work, which
    /// is the layout worth going back to when dragging has left them
    /// lopsided.
    func evenPanes(in windowWidth: CGFloat) {
        sidebarWidth = PaneLayout.sidebarComfortable
        guard showsUtility, windowWidth > 0 else {
            return
        }

        let share = (windowWidth - sidebarWidth) * PaneLayout.utilityShare
        utilityPaneWidth = min(max(share, PaneLayout.utilityRange.lowerBound), PaneLayout.utilityRange.upperBound)
        fitPanes(to: windowWidth)
    }

    /// What the detail shows with nothing selected: the first
    /// reading's progress until it lands, then the invitation.
    @ViewBuilder var unselectedDetail: some View {
        if dependencies.dashboard.hasLoaded == false {
            LaunchProgressView(
                "Reading repositories, worktrees and sessions…",
                waitingOn: "`git worktree list` for each repository and `herdr api snapshot`",
            )
        } else {
            ContentUnavailableView(
                "No worktree selected",
                systemImage: "rectangle.stack",
                description: Text("Pick a worktree on the left or create a session."),
            )
        }
    }

    /// Parses the persisted path-tab lines; values are tab names
    /// (unknown ones, including this store's old integer form, fall
    /// back to the default tab when read).
    static func decodeTabs(_ stored: String) -> [String: String] {
        var tabs = [String: String]()
        for line in stored.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if let path = parts.first, let name = parts.last, path != name {
                tabs[String(path)] = String(name)
            }
        }
        return tabs
    }

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
