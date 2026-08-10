import AgentIDEDomain
import Foundation
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

    func pastTitle(for past: TranscriptSession) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(past.modifiedAt))
            .formatted(.dateTime.day().month())
        let title = past.title.isEmpty
            ? String(past.id.prefix(Self.tabIDLength)) + "…"
            : String(past.title.prefix(Self.tabTitleLength))
        return date + " " + title
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

    private static let tabIDLength = 8
    private static let tabTitleLength = 24
}
