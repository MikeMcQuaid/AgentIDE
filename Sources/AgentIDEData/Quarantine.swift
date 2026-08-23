import AgentIDEDomain
import Foundation

/// Gatekeeper's quarantine on the agents' installs. A Homebrew cask
/// can leave `com.apple.quarantine` on what it installs; macOS then
/// assesses every exec of those files and, for an app without the
/// Developer Tools privilege, kills the process at exec with nothing
/// to say why. Terminal holds the privilege, so the same command
/// works there, which is the trap: Codex's command host died that
/// way from AgentIDE's panes alone. The privilege cannot be requested,
/// so the attribute is cleared from the agent's own install before
/// each launch, the `xattr -d` a user would otherwise run by hand.
enum Quarantine {
    // MARK: Internal

    /// Where Homebrew links agent commands.
    static let homebrewBinaries = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Clears the attribute from every file beside the agent's real
    /// binary, a cask's `bin` holding the helpers the agent launches,
    /// and returns the files it cleared.
    static func clear(for agent: AgentKind, binaryDirectories: [String] = homebrewBinaries) -> [String] {
        for directory in binaryDirectories {
            let link = directory + "/" + agent.rawValue
            guard FileManager.default.fileExists(atPath: link) else {
                continue
            }

            let install = URL(filePath: link).resolvingSymlinksInPath().deletingLastPathComponent()
            let files = try? FileManager.default.contentsOfDirectory(at: install, includingPropertiesForKeys: nil)
            return (files ?? []).map(\.path).filter(isQuarantined).sorted().filter(clear)
        }
        return []
    }

    // MARK: Private

    private static let attribute = "com.apple.quarantine"

    private static func isQuarantined(_ path: String) -> Bool {
        getxattr(path, attribute, nil, 0, 0, 0) >= 0
    }

    private static func clear(_ path: String) -> Bool {
        removexattr(path, attribute, 0) == 0
    }
}
