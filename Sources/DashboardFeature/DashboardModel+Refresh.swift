import AgentIDEData
import AgentIDEDomain
import Foundation
import UserNotifications

/// The poll and the one refresh path every action shares. Split from
/// the model body for length; the coalescing fields live there,
/// since extensions cannot hold state.
public extension DashboardModel {
    /// How often the system is re-read while the dashboard is alive,
    /// and the slower safety tick while the window is minimised or
    /// fully covered: nobody reads a hidden window, and notifications
    /// still fire, one tick later at worst.
    internal static let pollInterval = 5
    internal static let occludedPollInterval = 60

    /// Reloads everything and notifies about newly finished or
    /// newly unread sessions. Readings never stack: a call arriving
    /// while one runs waits for it and shares one follow-up with
    /// every other waiter, so the poll, a launch's listing retries
    /// and an action's refresh cost one reading between them rather
    /// than one each. Each caller still returns only after a reading
    /// that began at or after its call, which is the promise an
    /// action needs to see its own change land.
    func refresh(forcing repositoryPath: String? = nil) async {
        if let repositoryPath {
            pendingForces.insert(repositoryPath)
        }
        refreshRequests += 1
        let target = refreshRequests
        while completedRefreshes < target {
            if let running = refreshTask {
                await running.value
                continue
            }

            let covers = refreshRequests
            let task = Task { await performRefresh() }
            refreshTask = task
            await task.value
            refreshTask = nil
            completedRefreshes = max(completedRefreshes, covers)
        }
    }

    /// Polls the system on an interval while the dashboard is alive.
    /// Model discovery runs once per launch, so the pickers track the
    /// installed CLIs.
    func poll() async {
        // The sidebar and the restored selection come first: model
        // discovery and the notification prompt take seconds, and
        // the window showed "no worktree selected" while they ran.
        await refresh()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        // Each CLI is asked its models beside the others, not one
        // after another, and the answers are kept: the pickers open
        // on the last list at once and take the fresh one when it
        // lands, where waiting on the sandbox took twenty seconds.
        await discoverModels()
        publishSessionChoices()
        while Task.isCancelled == false {
            await refresh()
            let interval = isWindowVisible ? Self.pollInterval : Self.occludedPollInterval
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// One whole reading of the system; only `refresh` runs it, one
    /// at a time. The selected worktree is on screen, so its
    /// activity counts as seen; a manual unread mark survives.
    private func performRefresh() async {
        let forces = pendingForces
        pendingForces = []
        if let selection {
            service.acknowledgeActivity(worktreePath: selection.worktree.path)
        }
        let overview = await service.overview(scope: gitReadScope(forcing: forces), kept: groups)
        let listed = Self.retainingLostRows(of: groups, in: overview.groups)
        notifyChanges(from: groups, to: listed)
        groups = listed
        foreign = overview.foreign
        if let selected = selection {
            // A creation placeholder is never in a listing; it stays
            // selected until the creation replaces it.
            selection = listed.flatMap(\.items).first { $0.id == selected.id }
                ?? (selected.isPlaceholder ? selected : nil)
        } else if hasRestoredSelection == false {
            let stored = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
            selection = listed.flatMap(\.items).first { $0.worktree.path == stored }
        }
        hasRestoredSelection = true
        hasLoaded = true
        // herdr has answered, so nothing is waiting on it any more.
        awaitedSessions = []
        cacheSidebar(listed)
        await refreshStacks(of: listed)
        await refreshStalePullRequests(forcing: forces)
    }
}
