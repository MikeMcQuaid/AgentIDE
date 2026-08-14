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

    func sessionTitle(for session: AgentSession) -> String {
        let state = session.status == .running ? "●" : "○"
        return state + " " + (session.agent?.displayName ?? "Agent")
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
                    UtilityTabStrip()
                }
            }
            Spacer(minLength: 0)
            if utilityTab == .shell, hasRunningShell(at: item.worktree.path) {
                Button("Close shell") {
                    closeShell(at: item.worktree.path)
                }
                .controlSize(.small)
                .fixedSize()
                .hoverHelp("End this shell and its process immediately")
            }
            utilityToggleButton
                .fixedSize()
        }
        .padding(Self.stripSpacing)
    }

    func repository(of item: WorktreeItem) -> Repository {
        Repository(
            name: item.worktree.repositoryName,
            path: item.worktree.repositoryPath,
            fullName: nil,
        )
    }

    /// Opens the new session form preset to the item's repository.
    func newSession(for item: WorktreeItem) {
        dependencies.dashboard.newSessionRepository = repository(of: item)
        dependencies.dashboard.showsNewSession = true
    }

    /// Continues the worktree's most recent conversation: the newest
    /// transcript when one lists here, otherwise the recorded closed
    /// session. The state refreshes first, so a stale cached item
    /// never resumes over a session that is already live (tmux would
    /// try to attach without a terminal). Failures surface in the
    /// error log, so a resume that cannot launch says why.
    func resumeLatest(in item: WorktreeItem) async {
        await dependencies.dashboard.refresh()
        let fresh = dependencies.dashboard.groups.flatMap(\.items).first { $0.id == item.id } ?? item
        guard fresh.session == nil else {
            return
        }

        do {
            if let past = fresh.pastSessions.first {
                _ = try await dependencies.service.resumePast(past, worktree: fresh.worktree)
            } else {
                try await dependencies.service.resumeWorktree(fresh.worktree)
            }
        } catch {
            dependencies.dashboard.report(error.localizedDescription)
        }
        await sessionStarted()
    }

    func sessionStarted() async {
        await dependencies.dashboard.refresh()
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
        if let session = item.session {
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

    // MARK: Private

    private static let stripSpacing: CGFloat = 4
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
        .hoverHelp("Kill the tmux session; the worktree and conversation survive for resuming")
    }

    private func close(_ session: AgentSession, in item: WorktreeItem) async {
        try? await dependencies.service.closeSession(
            sessionName: session.name,
            worktreePath: item.worktree.path,
        )
        await dependencies.dashboard.refresh()
    }
}

// MARK: Utility tab content

extension RootView {
    /// The agent terminal: copies are prose, so multi-line copies
    /// reflow for pasting into chat and pull request bodies.
    func agentTerminal(for session: AgentSession) -> TerminalPaneView {
        TerminalPaneView(
            command: dependencies.service.attachCommand(sessionName: session.name),
            reflowsCopies: true,
        )
    }

    /// The host shell terminal, a plain local shell on the pane's
    /// own PTY: no server to wedge and nothing left behind when the
    /// app quits. Copies stay verbatim for code. The pane stays
    /// mounted behind other tabs, so it reports whether it is the
    /// visible one and yields keyboard focus otherwise.
    func shellTerminal(
        for worktree: Worktree,
        isActive: Bool,
        onExit: @escaping @MainActor () -> Void,
    ) -> TerminalPaneView {
        TerminalPaneView(
            shellIn: worktree.path,
            isActive: isActive,
            onProcessTerminated: onExit,
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
        switch utilityTab {
        case .shell:
            EmptyView()

        case .review:
            ReviewView(worktree: target.worktree, git: dependencies.git, service: dependencies.service)

        case .editor:
            EditorPane(worktreePath: item.worktree.path, service: dependencies.service)

        case .pullRequests:
            PullRequestsView(
                repository: Repository(name: target.worktree.repositoryName, path: target.worktree.repositoryPath),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
                store: dependencies.store,
                branch: target.worktree.branch,
            )

        case .browser:
            BrowserView()

        case .errors:
            ErrorsPane()
        }
    }
}
