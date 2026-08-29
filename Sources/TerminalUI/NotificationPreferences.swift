import Foundation

/// Which agent events notify and what each sounds like, set in the
/// Settings window. Every event defaults on; only the finish chime
/// has a default sound, matching what the app always did.
public enum NotificationPreferences {
    /// One notifiable agent event.
    public enum Event: CaseIterable, Sendable {
        case finished
        case needsInput
        case output

        // MARK: Public

        /// The toggle's storage key.
        public var enabledKey: String {
            switch self {
            case .finished:
                "notifyFinished"

            case .needsInput:
                "notifyNeedsInput"

            case .output:
                "notifyOutput"
            }
        }

        /// The sound path's storage key; the finish keeps the key
        /// the menu bar picker wrote, so an existing choice holds.
        public var soundKey: String {
            switch self {
            case .finished:
                CompletionSound.key

            case .needsInput:
                "needsInputSound"

            case .output:
                "outputSound"
            }
        }

        /// The sound played when none was chosen: the chime the
        /// finish always had, silence for the rest.
        public var defaultSound: String {
            self == .finished ? CompletionSound.defaultPath : ""
        }
    }

    /// Whether an event posts at all; absent means on.
    public static func notifies(_ event: Event) -> Bool {
        UserDefaults.standard.object(forKey: event.enabledKey) == nil
            || UserDefaults.standard.bool(forKey: event.enabledKey)
    }

    /// The event's chosen sound path; the empty string is silence.
    public static func sound(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.soundKey) ?? event.defaultSound
    }
}
