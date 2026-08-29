import AgentIDEDomain
import Foundation

/// Which appearance each agent session launched under. Agent TUIs
/// read the terminal's colours once at startup and trust them
/// forever, so the pane must keep drawing the palette the agent
/// believes in for the session's whole life, relaunches included.
public extension SessionService {
    /// The appearance a worktree's agent launched under; nil before
    /// any launch was recorded.
    func launchAppearance(worktreePath: String) -> TerminalAppearance? {
        switch store.load().terminalSchemes[worktreePath] {
        case Self.darkName:
            .dark

        case Self.lightName:
            .light

        default:
            nil
        }
    }

    /// Records the appearance a session is being born into, called
    /// by the launch funnel just before the agent starts.
    internal func rememberTerminalScheme(worktreePath: String) {
        // The system appearance, readable without AppKit: the key is
        // set to Dark in the global domain and absent in light mode.
        // Codex 0.148-0.150 misthemes its composer in both palettes;
        // forcing dark proved worse than the default, so every agent
        // follows the appearance it launched under.
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        store.update { metadata in
            metadata.terminalSchemes[worktreePath] = isDark ? Self.darkName : Self.lightName
        }
    }

    /// The strings the metadata file stores.
    private static var darkName: String {
        "dark"
    }

    private static var lightName: String {
        "light"
    }
}
