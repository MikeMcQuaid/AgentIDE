import AgentIDEDomain
import Foundation
import UserNotifications

/// Poll-to-poll change detection posting user notifications.
extension DashboardModel {
    func notifyChanges(from old: [RepositoryGroup], to new: [RepositoryGroup]) {
        // Uniquing, not trapping: duplicate ids would crash the poll.
        let oldItems = Dictionary(old.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        for item in new.flatMap(\.items) {
            guard let session = item.session, let previous = oldItems[item.id] else {
                continue
            }

            let finished = previous.session?.status == .running && session.status != .running
            let becameUnread = previous.hasUnread == false && item.hasUnread
            guard finished || becameUnread else {
                continue
            }

            post(
                title: finished ? "Agent finished" : "Agent output",
                body: "\(item.worktree.repositoryName): \(item.worktree.branch)",
            )
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
    }
}
