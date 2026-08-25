import AgentIDEDomain
import Foundation
import PRFeature
import ReviewFeature
import SessionFeature
import SwiftUI
import TerminalUI

/// The session tab identities, titles and capsule strip.
extension RootView {
    var sessionManagerBinding: Binding<Bool> {
        Binding(
            get: { dependencies.dashboard.showsSessionManager },
            set: { dependencies.dashboard.showsSessionManager = $0 },
        )
    }

    var utilityTab: UtilityTab {
        UtilityTab(rawValue: utilityTabName) ?? .review
    }

    func repositoryItems(for item: WorktreeItem) -> [WorktreeItem] {
        dependencies.dashboard
            .groups
            .first { $0.repository.path == item.worktree.repositoryPath }?
            .items ?? []
    }

    /// The version rather than the family alone: an agent whose CLI
    /// was upgraded while it ran goes on running the old one, and
    /// the number is the only place that shows.
    func sessionTitle(for session: AgentSession) -> String {
        let state = session.status == .running ? "●" : "○"
        let agent = session.agent?.displayName ?? "Agent"
        // The session name closes the line: it is the workspace
        // label herdr shows, so a pane here and a workspace there
        // can be matched by eye.
        return state + " " + agent + (session.version.map { " " + $0 } ?? "") + " · " + session.name
    }

    var utilityToggleButton: some View {
        Button {
            showsUtilityPane.toggle()
        } label: {
            Label("Toggle utility pane", systemImage: "sidebar.right")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .hoverHelp(
            showsUtilityPane
                ? "Hide the utility pane; View or Cmd-Shift-U brings it back"
                : "Show the utility pane",
        )
    }

    /// The tab bubbles and the pane toggle, with the shell's close
    /// button beside them while the shell tab shows a running shell.
    func utilityHeader(for item: WorktreeItem) -> some View {
        HStack(spacing: Self.stripSpacing) {
            // The tabs scroll when the pane narrows, so the toggle
            // beside them can never be squeezed out.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.stripSpacing) {
                    UtilityTabStrip(hiding: item.worktree.isHostDirectory ? [.editor] : [])
                }
            }
            Spacer(minLength: 0)
            if utilityTab == .shell, hasRunningShell(at: item.worktree.path) {
                Button {
                    closeShell(at: item.worktree.path)
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Close shell")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .fixedSize()
                .hoverHelp("End this shell and its process immediately")
            }
            utilityToggleButton
                .fixedSize()
        }
        .padding(Self.stripSpacing)
    }

    /// Everything the app has running, listed with what it costs.
    var sessionManager: some View {
        SessionManagerSheet(
            service: dependencies.service,
            onCloseBrowser: { closeBrowser(at: $0) },
            onDismiss: { dependencies.dashboard.showsSessionManager = false },
        )
    }

    /// A repository page's conversations, across all its worktrees.
    /// These pages render without a session strip, so the top inset
    /// keeps their header buttons out of the windowed titlebar's
    /// drag band and from under the floating utility toggle, which
    /// hid New session and Resume here everywhere but fullscreen.
    func repositoryConversations(for item: WorktreeItem) -> some View {
        RepositorySessionsView(
            repository: repository(of: item),
            service: dependencies.service,
            progress: dependencies.dashboard.launchProgress,
            onWorktreeFocus: { focusConversation(at: $0) },
            onNewSession: { startingSession = item.worktree.path },
            onResumed: { await dependencies.dashboard.refresh() },
        )
        .padding(.top, Self.toggleRowHeight)
    }

    /// One worktree's own past conversations, which can also start
    /// a fresh session in the same worktree.
    func worktreeConversations(for item: WorktreeItem) -> some View {
        RepositorySessionsView(
            repository: repository(of: item),
            service: dependencies.service,
            worktreePath: item.worktree.path,
            progress: dependencies.dashboard.launchProgress,
            onNewSession: { startingSession = item.worktree.path },
            onResumed: { await sessionStarted(in: item.worktree.path) },
        )
        .padding(.top, Self.toggleRowHeight)
    }

    /// The repository's default branch, which has no pull request
    /// of its own to go looking for.
    func defaultBranch(of item: WorktreeItem) -> String? {
        dependencies.dashboard
            .groups
            .first { $0.repository.path == item.worktree.repositoryPath }?
            .defaultBranch
    }

    func repository(of item: WorktreeItem) -> Repository {
        Repository(
            name: item.worktree.repositoryName,
            path: item.worktree.repositoryPath,
            fullName: nil,
        )
    }

    /// Continues the worktree's most recent conversation: the newest
    /// transcript when one lists here, otherwise the recorded closed
    /// session. The state refreshes first, so a stale cached item
    /// never resumes over a session that is already live (herdr would
    /// try to attach without a terminal). Failures surface in the
    /// error log, so a resume that cannot launch says why.
    func resumeLatest(in item: WorktreeItem) async {
        resumingWorktree = item.worktree.path
        defer {
            resumingWorktree = nil
        }
        await dependencies.dashboard.refresh()
        let fresh = dependencies.dashboard.groups.flatMap(\.items).first { $0.id == item.id } ?? item
        guard fresh.session == nil else {
            return
        }

        dependencies.dashboard.launchProgress.begin("Resuming")
        do {
            if let past = fresh.pastSessions.first {
                _ = try await dependencies.service.resumePast(past, worktree: fresh.worktree)
            } else {
                try await dependencies.service.resumeWorktree(fresh.worktree)
            }
        } catch {
            dependencies.dashboard.report(error.localizedDescription)
        }
        await sessionStarted(in: fresh.worktree.path)
    }

    /// The listing comes first: clearing the marker before it
    /// showed the worktree's conversations page for the moment until
    /// a reading found the live session.
    func sessionStarted(in worktreePath: String) async {
        await dependencies.dashboard.refreshUntil { items in
            items.contains { $0.worktree.path == worktreePath && $0.session?.status == .running }
        }
        startingSession = nil
    }

    /// Worktrees with a running session right now.
    var runningWorktreePaths: Set<String> {
        let items = dependencies.dashboard.groups.flatMap(\.items)
        return Set(items.filter { $0.session?.status == .running }.map(\.worktree.path))
    }

    /// Resumes each session that was running at sleep and died with
    /// it; the snapshot means surviving sessions stay untouched.
    func resumeKilled(sleepSnapshot: Set<String>) async {
        await dependencies.dashboard.refresh()
        let items = dependencies.dashboard.groups.flatMap(\.items)
        for path in sleepSnapshot.subtracting(runningWorktreePaths) {
            if let item = items.first(where: { $0.worktree.path == path }) {
                await resumeLatest(in: item)
            }
        }
    }

    /// Stages dropped files where the sandbox can read them and
    /// types the staged paths into the session, ready to send.
    func dropFiles(_ urls: [URL], into sessionName: String) -> Bool {
        guard urls.isEmpty == false else {
            return false
        }

        Task {
            do {
                for url in urls {
                    let staged = try dependencies.service.stageDroppedFile(at: url)
                    try await dependencies.service.typeText(staged + " ", sessionName: sessionName)
                }
            } catch {
                dependencies.dashboard.report(error.localizedDescription)
            }
        }
        return true
    }

    /// The live session's status row at the top of the primary pane:
    /// its state and agent beside the close button. Past
    /// conversations live in the conversation list instead, so this
    /// only shows while a session runs. In-pane rather than in the
    /// window toolbar, whose items reflowed across the split on
    /// this OS.
    @ViewBuilder
    func sessionStrip(for item: WorktreeItem) -> some View {
        if item.worktree.isHostDirectory {
            HStack(spacing: Self.stripSpacing) {
                Label(item.worktree.path, systemImage: "laptopcomputer")
                    .font(.callout)
                    .padding(.horizontal, Self.tabHorizontalPadding)
                    .padding(.vertical, Self.tabVerticalPadding)
                Spacer(minLength: 0)
            }
            .padding(Self.stripSpacing)
            .hoverHelp("A directory of your own: this shell runs as you, and no agent runs here")
            Divider()
        } else if let session = item.session {
            HStack(spacing: Self.stripSpacing) {
                Text(sessionTitle(for: session))
                    .font(.callout)
                    .padding(.horizontal, Self.tabHorizontalPadding)
                    .padding(.vertical, Self.tabVerticalPadding)
                closeSessionButton(session, in: item)
                Spacer(minLength: 0)
            }
            .padding(Self.stripSpacing)
            .hoverHelp("The live session; closing keeps the conversation resumable")
            Divider()
        }
    }

    // MARK: Private

    static let stripSpacing: CGFloat = 4

    /// What keeps an agent's output off the pane's edges.
    static let terminalInset: CGFloat = 6
    private static let tabHorizontalPadding: CGFloat = 8
    private static let tabVerticalPadding: CGFloat = 3

    /// Beside the live session's title, since that is what it closes.
    private func closeSessionButton(_ session: AgentSession, in item: WorktreeItem) -> some View {
        Button {
            Task { await close(session, in: item) }
        } label: {
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close session")
        }
        .buttonStyle(.plain)
        .hoverHelp("End the session and its workspace now; the worktree and conversation survive for resuming")
    }

    private func close(_ session: AgentSession, in item: WorktreeItem) async {
        // The pane goes now, not when herdr has been asked again.
        dependencies.dashboard.forgetSession(at: item.worktree.path)
        await dependencies.service.closeSession(sessionName: session.name, worktree: item.worktree)
        await dependencies.dashboard.refresh()
    }
}

// MARK: Utility tab content

extension RootView {
    /// The agent terminal: copies are prose, so multi-line copies
    /// reflow for pasting into chat and pull request bodies.
    func agentTerminal(for session: AgentSession, at worktreePath: String, isActive: Bool) -> some View {
        TerminalPaneView(
            command: session.paneID.map(dependencies.service.attachCommand(paneID:)) ?? [],
            reflowsCopies: true,
            isActive: isActive,
            fixedAppearance: dependencies.service.launchAppearance(worktreePath: worktreePath),
        )
        // A hair of room either side: the agent's own frames draw to
        // their last column, which sat against the pane's edges.
        .padding(.horizontal, Self.terminalInset)
    }

    /// The host shell terminal, a plain local shell on the pane's
    /// own PTY: no server to wedge and nothing left behind when the
    /// app quits. Copies stay verbatim for code. The pane stays
    /// mounted behind other tabs, worktrees and pages, so it reports
    /// whether it is the visible one and yields keyboard focus
    /// otherwise.
    func shellTerminal(
        at path: String,
        onExit: @escaping @MainActor () -> Void,
        isActive: Bool,
    ) -> TerminalPaneView {
        TerminalPaneView(
            shellIn: path,
            environment: dependencies.service.shellEnvironment(),
            isActive: isActive,
            onProcessTerminated: onExit,
        )
    }

    /// The one editor, wherever it shows: the utility pane for a
    /// worktree, the primary pane for a directory of your own.
    func editorPane(for item: WorktreeItem) -> EditorPane {
        EditorPane(
            worktreePath: item.worktree.path,
            service: dependencies.service,
            // The closure stays a non-final argument: the formatter
            // rewrites a trailing one after a multiline call.
            onFinishedWaiting: { finishedWaitingEdit() },
            waitingEdit: waitingEdit(in: item.worktree.path),
        )
    }

    /// The worktree the review surfaces describe: on the repository
    /// page, the conversation selected in the list wins, so clicking
    /// around conversations retargets Review and PRs.
    func reviewTarget(for item: WorktreeItem, conversationPath: String?) -> WorktreeItem {
        guard item.worktree.path == item.worktree.repositoryPath,
              let path = conversationPath,
              let match = repositoryItems(for: item).first(where: { $0.worktree.path == path })
        else {
            return item
        }

        return match
    }

    /// The non-terminal utility tabs' content.
    @ViewBuilder
    func switchedUtility(for item: WorktreeItem, conversationPath: String?) -> some View {
        let target = reviewTarget(for: item, conversationPath: conversationPath)
        // A directory of your own edits in the primary pane, so a
        // request for the editor here, from opening a file in the
        // diff or from the tab it was last on, shows the diff
        // instead of a second editor.
        // Review, the editor and the pull requests stay mounted and
        // hide, rather than being rebuilt on every tab switch: each
        // costs a git or GitHub read to come back, and flipping
        // between them showed a loading state every time.
        let shown = utilityTab == .editor && item.worktree.isHostDirectory ? UtilityTab.review : utilityTab
        // Top-aligned, as each of these was before they shared a
        // stack: a pane with nothing in it belongs at the top of the
        // pane, not floating in the middle of it.
        return ZStack(alignment: .top) {
            ReviewView(
                worktree: target.worktree,
                git: dependencies.git,
                github: dependencies.github,
                service: dependencies.service,
            )
            .hidden(shown != .review)
            editorPane(for: item)
                .hidden(shown != .editor)
            PullRequestsView(
                repository: Repository(
                    name: target.worktree.repositoryName,
                    path: target.worktree.isHostDirectory
                        ? target.worktree.path
                        : target.worktree.repositoryPath,
                ),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
                store: dependencies.store,
                branch: target.worktree.branch,
                worktreePath: target.worktree.path,
                defaultBranch: defaultBranch(of: item),
                isMainCheckout: target.worktree.path == target.worktree.repositoryPath,
            )
            .hidden(shown != .pullRequests)
            if shown == .errors {
                ErrorsPane()
            }
        }
    }
}
