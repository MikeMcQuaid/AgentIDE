import Foundation

/// How often the dashboard re-reads the system, and when a tick may
/// ask herdr for its pane listing rather than reuse the last one.
///
/// Events do the real work: a file changing under a worktree, an
/// agent changing state, an action of the app's own. The tick is the
/// safety net under them, and a safety net on battery can be slow:
/// every tick that asks herdr is a `sudo` login shell, and a machine
/// on battery with nothing happening should cost nothing.
public enum RefreshCadence {
    /// The slowest a window on battery ticks while it shows.
    public static let batteryPollSeconds = 60

    /// The tick while the window is minimised or covered.
    public static let occludedPollSeconds = 60

    /// The same on battery.
    public static let batteryOccludedPollSeconds = 300

    /// The safety interval under the pane listing, plugged in.
    public static let panesSeconds: TimeInterval = 60

    /// The same on battery.
    public static let batteryPanesSeconds: TimeInterval = 300

    /// How far apart the pane load readings are, plugged in.
    public static let paneLoadSeconds: TimeInterval = 30

    /// The same on battery.
    public static let batteryPaneLoadSeconds: TimeInterval = 300

    /// How much slower every safety interval runs on battery.
    public static let batterySlowdown: TimeInterval = 5

    /// The tick while the window shows and the machine is plugged
    /// in, as Settings has it.
    public static func pollSeconds(setting: Int, visible: Bool, onBattery: Bool) -> Int {
        switch (visible, onBattery) {
        case (true, false):
            setting

        case (true, true):
            max(setting, batteryPollSeconds)

        case (false, false):
            occludedPollSeconds

        case (false, true):
            batteryOccludedPollSeconds
        }
    }

    /// Whether a tick asks herdr for the pane listing. Actions and
    /// agent changes always do; the tick itself does so only when
    /// its safety interval has passed, since the listing changes
    /// only when a session starts, ends or changes state, and every
    /// one of those already wakes a reading of its own.
    public static func panesDue(lastRead: Date?, now: Date, onBattery: Bool) -> Bool {
        guard let lastRead else {
            return true
        }

        return now.timeIntervalSince(lastRead) >= (onBattery ? batteryPanesSeconds : panesSeconds)
    }

    /// A safety interval as it stands on battery: five times longer.
    /// Every interval that only guards against a lost event or a
    /// stale answer slows by this one factor, so a machine on battery
    /// has one cadence rather than a dozen numbers to reason about.
    public static func slowed(_ interval: TimeInterval, onBattery: Bool) -> TimeInterval {
        if onBattery {
            interval * batterySlowdown
        } else {
            interval
        }
    }

    /// How far apart the pane load readings (one `ps`) are.
    public static func paneLoadSeconds(onBattery: Bool) -> TimeInterval {
        if onBattery {
            batteryPaneLoadSeconds
        } else {
            paneLoadSeconds
        }
    }
}
