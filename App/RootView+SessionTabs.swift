import AgentIDEDomain
import Foundation
import PRFeature
import ReviewFeature
import SessionFeature
import SwiftUI

/// The session tab identities, titles and capsule strip.
extension RootView {
    static let activeTabID = "active"
    static let newTabID = "new"

    var newSessionBinding: Binding<Bool> {
        Binding(
            get: { dependencies.dashboard.showsNewSession },
            set: { dependencies.dashboard.showsNewSession = $0 },
        )
    }

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

    // MARK: Private

    private static let tabTitleLength = 24
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

        case .message:
            FinalMessageView(
                item: item,
                service: dependencies.service,
                hasOpenPullRequest: dependencies.dashboard.pullRequest(for: item) != nil,
            )
        }
    }
}
