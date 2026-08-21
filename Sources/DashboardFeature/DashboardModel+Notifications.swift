import AgentIDEDomain
import AppKit
import Foundation
import UserNotifications

/// Poll-to-poll change detection posting user notifications. One
/// notification per worktree per poll, the most decided state first:
/// an exit or a completed turn beats needing input beats new output.
extension DashboardModel {
    func notifyChanges(from old: [RepositoryGroup], to new: [RepositoryGroup]) {
        // Uniquing, not trapping: duplicate ids would crash the poll.
        let oldItems = Dictionary(old.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        for item in new.flatMap(\.items) {
            guard let session = item.session, let previous = oldItems[item.id] else {
                continue
            }

            let body = "\(item.worktree.repositoryName): \(item.worktree.branch)"
            let exited = previous.session?.status == .running && session.status != .running
            let completedTurn = previous.session?.activity == .working && session.activity == .idle
            if exited || completedTurn {
                post(title: "Agent finished", body: body, chimes: true)
            } else if previous.session?.activity != .blocked, session.activity == .blocked {
                post(title: "Agent needs input", body: body)
            } else if previous.hasUnread == false, item.hasUnread {
                post(title: "Agent output", body: body)
            }
        }
    }

    private func post(title: String, body: String, chimes: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
        if chimes {
            // A named system sound, so no audio file ships in the
            // repository; NSSound plays whether or not notification
            // banners are allowed to.
            NSSound(named: "Glass")?.play()
        }
    }
}
