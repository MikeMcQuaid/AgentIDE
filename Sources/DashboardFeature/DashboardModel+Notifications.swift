import AgentIDEDomain
import AppKit
import Foundation
import TerminalUI
import UserNotifications

/// Poll-to-poll change detection posting user notifications. One
/// notification per worktree per poll, the most decided state first:
/// a completed turn beats needing input beats new output. Settings
/// decides which events notify and what each sounds like; an exit
/// posts nothing of its own, the stop icon and unread dot carry it.
extension DashboardModel {
    func notifyChanges(from old: [RepositoryGroup], to new: [RepositoryGroup]) {
        // Uniquing, not trapping: duplicate ids would crash the poll.
        let oldItems = Dictionary(old.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        for item in new.flatMap(\.items) {
            guard let session = item.session, let previous = oldItems[item.id] else {
                continue
            }

            let body = "\(item.worktree.repositoryName): \(item.worktree.branch)"
            let completedTurn = previous.session?.activity == .working && session.activity == .done
            if completedTurn {
                post(.done, title: "Agent finished", body: body)
                // The turn is assumed to have committed, so the
                // branch's pull request stamps are forgotten here,
                // just before this same reading's pull request pass:
                // it re-asks at once instead of waiting out the tier.
                pullRequests.invalidateBranch(
                    repositoryPath: item.worktree.repositoryPath,
                    branch: item.worktree.branch,
                )
            } else if previous.session?.activity != .blocked, session.activity == .blocked {
                post(.blocked, title: "Agent needs input", body: body)
            } else if previous.hasActionableUnread == false, item.hasActionableUnread {
                // Only output that pauses for you counts; streaming
                // output notified per burst with nothing to do.
                post(.output, title: "Agent output", body: body)
            }
        }
        updateDockBadge(for: new)
    }

    // MARK: Private

    /// The Dock badge counts the worktrees needing attention, each
    /// contribution behind its Settings toggle: an agent waiting on
    /// input, a done or exited turn not yet viewed, or unread
    /// output anywhere but the selected worktree of the focused
    /// window, the one pane demonstrably being read.
    private func updateDockBadge(for groups: [RepositoryGroup]) {
        let focusedPath = NSApp.isActive ? selection?.worktree.path : nil
        let attention = groups.flatMap(\.items).count { item in
            let unseen = item.hasActionableUnread && item.worktree.path != focusedPath
            let blocked = item.session?.activity == .blocked
                && NotificationPreferences.badges(.blocked)
            let doneUnseen = item.session?.activity == .done && unseen
                && NotificationPreferences.badges(.done)
            let outputUnseen = unseen && NotificationPreferences.badges(.output)
            return blocked || doneUnseen || outputUnseen
        }
        NSApp.dockTile.badgeLabel = attention > 0 ? String(attention) : nil
    }

    private func post(_ event: NotificationPreferences.Event, title: String, body: String) {
        guard NotificationPreferences.notifies(event) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
        // The event's chosen sound plays whether or not banners are
        // allowed to; silence is a choice.
        CompletionSound.play(path: NotificationPreferences.sound(for: event))
    }
}
