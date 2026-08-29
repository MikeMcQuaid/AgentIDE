import Foundation

/// Which agent events notify, chime and count in the Dock badge,
/// set in the Settings window. Every toggle defaults on; only the
/// completed turn has a default sound, matching what the app always
/// did, and new output deliberately has no sound at all: it would
/// chime per burst until the turn ended.
public enum NotificationPreferences {
    // MARK: Public

    /// One notifiable agent event.
    public enum Event: CaseIterable, Sendable {
        case done
        case blocked
        case output

        // MARK: Public

        /// The notify toggle's storage key; done and blocked keep
        /// the keys the earlier three-event settings wrote, so an
        /// existing choice holds.
        public var enabledKey: String {
            switch self {
            case .done:
                "notifyFinished"

            case .blocked:
                "notifyNeedsInput"

            case .output:
                "notifyOutput"
            }
        }

        /// The Dock badge toggle's storage key.
        public var badgeKey: String {
            switch self {
            case .done:
                "badgeDone"

            case .blocked:
                "badgeNeedsInput"

            case .output:
                "badgeOutput"
            }
        }

        /// The sound path's storage key; nil for output, which never
        /// chimes. The completed turn keeps the key the original
        /// picker wrote.
        public var soundKey: String? {
            switch self {
            case .done:
                CompletionSound.key

            case .blocked:
                "needsInputSound"

            case .output:
                nil
            }
        }

        /// The sound played when none was chosen: the chime the
        /// completed turn always had, a ping for the one state that
        /// needs a person, silence for the rest.
        public var defaultSound: String {
            switch self {
            case .done:
                CompletionSound.defaultPath

            case .blocked:
                "/System/Library/Sounds/Ping.aiff"

            case .output:
                ""
            }
        }
    }

    /// Whether an event posts at all; absent means on.
    public static func notifies(_ event: Event) -> Bool {
        boolDefaultingTrue(event.enabledKey)
    }

    /// Whether an event's worktrees count in the Dock badge; absent
    /// means on.
    public static func badges(_ event: Event) -> Bool {
        boolDefaultingTrue(event.badgeKey)
    }

    /// The event's chosen sound path; the empty string is silence.
    public static func sound(for event: Event) -> String {
        guard let key = event.soundKey else {
            return ""
        }

        return UserDefaults.standard.string(forKey: key) ?? event.defaultSound
    }

    // MARK: Private

    private static func boolDefaultingTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }
}
