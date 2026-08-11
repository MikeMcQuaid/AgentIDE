import AgentIDEDomain
import Foundation
import PRFeature
import ReviewFeature
import SessionFeature
import SwiftUI
import TerminalUI

/// The session tab identities, titles and capsule strip.
extension RootView {
    static let activeTabID = "active"
    static let newTabID = "new"

    var sessionManagerBinding: Binding<Bool> {
        Binding(
            get: { dependencies.dashboard.showsSessionManager },
            set: { dependencies.dashboard.showsSessionManager = $0 },
        )
    }

    var utilityTab: UtilityTab {
        let tabs = UtilityTab.allCases
        return tabs.indices.contains(utilityTabIndex) ? tabs[utilityTabIndex] : .shell
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

    /// A short date and time; never the transcript's uuid, which
    /// reads as noise.
    func pastTitle(for past: TranscriptSession) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(past.modifiedAt))
            .formatted(.dateTime.day().month().hour().minute())
        guard past.title.isEmpty else {
            return date + " " + String(past.title.prefix(Self.tabTitleLength))
        }

        return date
    }

    func initialTab(for item: WorktreeItem) -> String {
        if item.session != nil {
            Self.activeTabID
        } else if let past = item.pastSessions.first {
            past.id
        } else {
            Self.newTabID
        }
    }

    /// The worktree's sessions as capsule tabs at the top of the
    /// primary pane; hidden when there is nothing to pick between.
    /// In-pane rather than in the window toolbar, whose items
    /// reflowed across the split on this OS. The selection rides a
    /// binding, because the state itself stays private to the view.
    @ViewBuilder
    func sessionStrip(for item: WorktreeItem, selection: Binding<String>) -> some View {
        if item.session != nil || item.pastSessions.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.stripSpacing) {
                    if let session = item.session {
                        sessionTabButton(
                            title: sessionTitle(for: session),
                            id: Self.activeTabID,
                            selection: selection,
                        )
                        closeSessionButton(session, in: item)
                    }
                    ForEach(item.pastSessions) { past in
                        sessionTabButton(title: pastTitle(for: past), id: past.id, selection: selection)
                    }
                }
                .padding(Self.stripSpacing)
            }
            .hoverHelp("The worktree's sessions: the live one and past conversations")
            Divider()
        }
    }

    /// Parses the persisted path-tab lines.
    static func decodeTabs(_ stored: String) -> [String: Int] {
        var tabs = [String: Int]()
        for line in stored.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if let path = parts.first, let index = parts.last.flatMap({ Int($0) }), parts.first != parts.last {
                tabs[String(path)] = index
            }
        }
        return tabs
    }

    // MARK: Private

    private static let tabTitleLength = 24
    private static let stripSpacing: CGFloat = 4
    private static let tabHorizontalPadding: CGFloat = 8
    private static let tabVerticalPadding: CGFloat = 3
    private static let tabSelectedOpacity = 0.25

    private func sessionTabButton(title: String, id: String, selection: Binding<String>) -> some View {
        Button {
            selection.wrappedValue = id
        } label: {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, Self.tabHorizontalPadding)
                .padding(.vertical, Self.tabVerticalPadding)
                .background(
                    Capsule().fill(
                        selection.wrappedValue == id
                            ? Color.accentColor.opacity(Self.tabSelectedOpacity)
                            : .clear,
                    ),
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Beside the live session's tab, since that is what it closes.
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
    /// The non-terminal utility tabs' content.
    @ViewBuilder
    func switchedUtility(for item: WorktreeItem) -> some View {
        switch utilityTab {
        case .shell:
            EmptyView()

        case .review:
            ReviewView(worktree: item.worktree, git: dependencies.git, service: dependencies.service)

        case .editor:
            EditorPane(worktreePath: item.worktree.path, service: dependencies.service)

        case .pullRequests:
            PullRequestsView(
                repository: Repository(name: item.worktree.repositoryName, path: item.worktree.repositoryPath),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
                branch: item.worktree.branch,
            )

        case .browser:
            BrowserView()
        }
    }
}
