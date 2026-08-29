import AgentIDEDomain
import Foundation
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

    var utilityToggleButton: some View {
        Button {
            showsUtilityPane.toggle()
        } label: {
            Label("Toggle utility pane", systemImage: "sidebar.right")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .hoverHelp(
            showsUtilityPane ? "Hide the utility pane" : "Show the utility pane",
            shortcut: "⇧⌘U",
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
        let context = item.worktree.path
        dependencies.dashboard.launchProgress.begin("Resuming")
        // The item on screen is checked against herdr alone: a full
        // refresh reads every worktree's git state too, which is
        // seconds on a wide sidebar, to answer one yes-or-no.
        let alive = await PerformanceLog.time(.process, "resume: is a session already live", context: context) {
            await dependencies.service.hasLiveSession(worktreePath: item.worktree.path)
        }
        guard alive == false else {
            return
        }

        do {
            try await PerformanceLog.time(.process, "resume: launch", context: context) {
                if let past = item.pastSessions.first {
                    let name = try await dependencies.service.resumePast(past, worktree: item.worktree)
                    // herdr says when the resumed agent settles, so
                    // the listing loop after finds it first time.
                    await dependencies.service.waitForAgentReady(sessionName: name)
                } else {
                    try await dependencies.service.resumeWorktree(item.worktree)
                }
            }
        } catch {
            dependencies.dashboard.report(error.localizedDescription)
        }
        await PerformanceLog.time(.process, "resume: list until running", context: context) {
            await sessionStarted(in: item.worktree.path)
        }
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
            // The agent's mark at the left (colour while connected,
            // greyscale once ended), the herdr workspace name
            // centred, the close button at the pane's far edge;
            // each part explains itself on hover.
            ZStack {
                HStack(spacing: Self.stripSpacing) {
                    agentMark(for: session)
                        .padding(.leading, Self.tabHorizontalPadding)
                    stateGlyph(for: session)
                    Spacer(minLength: 0)
                    closeSessionButton(session, in: item)
                        .padding(.trailing, Self.tabHorizontalPadding)
                }
                Text(session.name)
                    // Monospaced: it is the workspace label herdr
                    // shows, matched by eye against terminal output.
                    .font(.callout.monospaced())
                    .padding(.vertical, Self.tabVerticalPadding)
                    .hoverHelp("The herdr workspace name; `script/attach " + session.name
                        + "` joins this session from a terminal")
            }
            .padding(Self.stripSpacing)
            Divider()
        }
    }

    // MARK: Private

    static let stripSpacing: CGFloat = 4

    /// What keeps an agent's output off the pane's edges.
    static let terminalInset: CGFloat = 6
    private static let tabHorizontalPadding: CGFloat = 8
    private static let tabVerticalPadding: CGFloat = 3

    /// The brand mark beside the live session's title, sized to the
    /// callout text beside it.
    private static let agentIconSize: CGFloat = 15

    /// The agent's brand mark, doubling as the connection light: in
    /// colour while the process runs, greyscale once it has ended.
    /// The tooltip carries the CLI version, which matters because an
    /// agent upgraded while running goes on running the old one, and
    /// this is the only place that shows.
    @ViewBuilder
    private func agentMark(for session: AgentSession) -> some View {
        let name = session.agent?.displayName ?? "Agent"
        let version = session.version.map { " " + $0 } ?? ""
        let isRunning = session.status == .running
        let state = isRunning
            ? "connected and running"
            : "ended; the conversation stays resumable"
        if let agent = session.agent {
            Image(isRunning ? agent.connectedIconAssetName : agent.iconAssetName)
                .renderingMode(isRunning ? .original : .template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                .foregroundStyle(.secondary)
                .accessibilityLabel(name + (isRunning ? ", connected" : ", ended"))
                .hoverHelp(name + version + ": " + state)
        } else {
            Image(systemName: "questionmark.circle")
                .accessibilityLabel("Unknown agent")
                .hoverHelp("An agent this app does not recognise: " + state)
        }
    }

    /// The activity glyph beside the mark, the sidebar's vocabulary
    /// at strip size; only working moves, because only working is
    /// happening right now.
    @ViewBuilder
    private func stateGlyph(for session: AgentSession) -> some View {
        switch (session.status, session.activity) {
        case (.finished, _):
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Exited")
                .hoverHelp("The process exited; the conversation stays resumable")

        case (.running, .working):
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
                .accessibilityLabel("Working")
                .hoverHelp("The agent is working on its turn")

        case (.running, .done):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Done")
                .hoverHelp("The turn is done; the answer is waiting")

        case (.running, .idle):
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Idle")
                .hoverHelp("At rest: nothing asked, or the turn was interrupted")

        case (.running, .blocked):
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Needs input")
                .hoverHelp("The agent asked a question or wants an approval")

        case (.running, nil):
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Undetected")
                .hoverHelp("Running, but herdr cannot tell what the agent is doing")
        }
    }

    /// At the pane's far edge, clear of the name it closes.
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
