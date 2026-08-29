import Foundation

/// The user preferences the Settings window edits, read where each
/// applies. One place holds the keys and defaults so the window and
/// the readers can never disagree; every value is derived state the
/// app works without, per the metadata rules.
public enum AppSettings {
    // MARK: Public

    /// The poll cadence's storage key, in seconds.
    public static let pollIntervalKey = "pollIntervalSeconds"

    /// The stack re-derivation cadence's storage key, in seconds.
    public static let stackIntervalKey = "stackRefreshSeconds"

    /// The idle-sleep inhibition toggle's storage key.
    public static let inhibitsSleepKey = "inhibitsSleepWhileWorking"

    /// The signing requirement toggle's storage key.
    public static let requireSignedCommitsKey = "requireSignedCommits"

    /// The external editor command's storage key.
    public static let externalEditorKey = "externalEditorCommand"

    /// The Cmd-click browser's storage key, an application path;
    /// empty means the system's default browser.
    public static let externalBrowserKey = "externalBrowser"

    /// The repositories directory override's storage key; empty
    /// keeps the shared workspace's own.
    public static let repositoriesDirectoryKey = "repositoriesDirectory"

    /// The worktrees directory override's storage key.
    public static let worktreesDirectoryKey = "worktreesDirectory"

    /// The monospace face's storage key.
    public static let codeFontNameKey = "codeFontName"

    /// The monospace point size's storage key.
    public static let codeFontSizeKey = "codeFontSize"

    /// How often the system is re-read while the window shows.
    public static var pollInterval: Int {
        let stored = UserDefaults.standard.integer(forKey: pollIntervalKey)
        return stored > 0 ? stored : defaultPollInterval
    }

    /// How long a derived stack is trusted before re-deriving.
    public static var stackInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: stackIntervalKey)
        return stored > 0 ? stored : defaultStackInterval
    }

    /// Whether running agents and shells block idle sleep.
    public static var inhibitsSleep: Bool {
        boolDefaultingTrue(inhibitsSleepKey)
    }

    /// Whether pushing demands a signed tip. On by default: the
    /// sandbox cannot sign and unsigned pushes are normally blocked
    /// by hooks, but a repository without that hook may not care.
    public static var requiresSignedCommits: Bool {
        boolDefaultingTrue(requireSignedCommitsKey)
    }

    // MARK: Internal

    static let defaultPollInterval = 5
    static let defaultStackInterval: TimeInterval = 60

    // MARK: Private

    /// A toggle whose absence means true, so existing behaviour
    /// holds until the user turns it off.
    private static func boolDefaultingTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }
}
