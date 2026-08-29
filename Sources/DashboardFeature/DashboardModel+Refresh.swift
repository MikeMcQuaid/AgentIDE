import AgentIDEData
import AgentIDEDomain
import Foundation
import UserNotifications

/// The poll and the one refresh path every action shares. Split from
/// the model body for length; the coalescing fields live there,
/// since extensions cannot hold state.
public extension DashboardModel {
    /// How often the system is re-read while the dashboard is alive
    /// (Settings can slow it), and the slower safety tick while the
    /// window is minimised or fully covered: nobody reads a hidden
    /// window, and notifications still fire, one tick later at worst.
    internal static var pollInterval: Int {
        AppSettings.pollInterval
    }

    internal static let occludedPollInterval = 60

    /// Reloads everything and notifies about newly finished or
    /// newly unread sessions. Readings never stack: at most one
    /// runs and one waits, and a call arriving while one runs joins
    /// the queued follow-up with every other waiter, so the poll, a
    /// launch's listing retries and an action's refresh cost one
    /// reading between them rather than one each. Each caller still
    /// returns only after a reading begun at or after its call, the
    /// promise an action needs to see its own change land. No
    /// waiting loop: awaiting an already-finished task resumes
    /// without yielding the actor, and a loop of waiters doing that
    /// starved the one task able to move the state on, which hung
    /// the app at startup.
    func refresh(forcing repositoryPath: String? = nil) async {
        if let repositoryPath {
            pendingForces.insert(repositoryPath)
        }
        // A queued reading has not started, so it must begin after
        // this call: joining it keeps the promise.
        if let queued = queuedRefresh {
            await queued.value
            return
        }
        if let running = refreshTask {
            let queued = Task {
                await running.value
                // Promote: this run is now the current one, and the
                // queued slot opens for the next caller. The slot
                // still holds this task, since joiners never
                // replace a queued reading.
                refreshTask = queuedRefresh
                queuedRefresh = nil
                await performRefresh()
                refreshTask = nil
            }
            queuedRefresh = queued
            await queued.value
            return
        }

        let task = Task {
            await performRefresh()
            refreshTask = nil
        }
        refreshTask = task
        await task.value
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
