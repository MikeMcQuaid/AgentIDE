import Foundation

/// What a pane's process tree is costing the machine, and whether it
/// has cost that much for long enough to be worth telling anyone.
///
/// One worktree can starve every other: a linter that spins takes
/// eight cores and every pane in the window looks hung, with nothing
/// on screen saying which one is doing it or what it is running.
public struct PaneLoad: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a reading.
    public init(percent: Double, busiest: String, since: Date) {
        self.percent = percent
        self.busiest = busiest
        self.since = since
    }

    // MARK: Public

    /// The CPU a tree holds before it is worth watching, in percent
    /// of one core: three cores, which an agent waiting on a model
    /// never approaches and a parallel build passes at once.
    public static let busyPercent: Double = 300

    /// How long it must hold that before a row says so. Ten
    /// minutes, because a repository's own test suite legitimately
    /// holds five cores for several of them: a badge that lit for
    /// every honest test run would be one nobody reads by the time a
    /// linter spins for half an hour.
    public static let patience: TimeInterval = 600

    /// The tree's summed CPU, in percent of one core.
    public let percent: Double

    /// The heaviest process in the tree, named as `ps` names it: the
    /// answer to "what is it doing", which a percentage alone never
    /// gives.
    public let busiest: String

    /// When this busy spell started.
    public let since: Date

    /// When the current spell started: now for a tree that has just
    /// gone busy, unchanged for one that was already busy, and
    /// nothing at all once it drops back. A reading below the
    /// threshold ends the spell, so a build that finishes is
    /// forgotten rather than remembered as a spell that paused.
    public static func busySince(_ started: Date?, percent: Double, now: Date = Date()) -> Date? {
        guard percent >= busyPercent else {
            return nil
        }

        return started ?? now
    }

    /// Whether this reading has lasted long enough to show.
    public func isHeavy(now: Date = Date()) -> Bool {
        now.timeIntervalSince(since) >= Self.patience
    }

    /// What the row says on hover: what is running, what it costs
    /// and how long it has cost it.
    public func summary(now: Date = Date()) -> String {
        let minutes = max(Int(now.timeIntervalSince(since) / Self.secondsPerMinute), 1)
        return busiest + " has held " + String(Int(percent)) + "% of the CPU here for "
            + String(minutes) + (minutes == 1 ? " minute" : " minutes")
    }

    // MARK: Private

    /// Seconds in the minutes the summary counts.
    private static let secondsPerMinute: Double = 60
}
