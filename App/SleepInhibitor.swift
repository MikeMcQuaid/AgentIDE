import AgentIDEData
import Foundation

/// Holds a system activity that blocks idle sleep while agents or
/// shells run, so the machine never sleeps mid-response. Closing the
/// lid still sleeps; only idle sleep is deferred.
@MainActor
final class SleepInhibitor {
    // MARK: Lifecycle

    deinit {
        // The activity dies with the process either way.
    }

    // MARK: Internal

    func update(hasLiveWork: Bool) {
        if hasLiveWork, AppSettings.inhibitsSleep, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "Agent sessions or shells are running",
            )
        } else if hasLiveWork == false || AppSettings.inhibitsSleep == false,
                  let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    // MARK: Private

    private var activity: NSObjectProtocol?
}
