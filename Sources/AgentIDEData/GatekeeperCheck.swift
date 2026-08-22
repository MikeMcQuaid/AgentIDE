import AgentIDEDomain
import Foundation

/// Whether Gatekeeper will kill the agents' helper binaries when
/// AgentIDE runs them. A Homebrew cask can leave
/// `com.apple.quarantine` on what it installs; macOS then assesses
/// every exec of those files and, for an app without the Developer
/// Tools privilege, kills the process at exec with nothing to say
/// why. Terminal holds the privilege, so the same command works
/// there, which is the trap: Codex's command host died that way from
/// AgentIDE's panes alone.
public struct GatekeeperCheck: Sendable {
    // MARK: Lifecycle

    /// Creates a check over the directories agent commands are
    /// installed into.
    public init(runner: any ProcessRunner, binaryDirectories: [String] = Self.homebrewBinaries) {
        self.runner = runner
        self.binaryDirectories = binaryDirectories
    }

    // MARK: Public

    /// Where Homebrew links agent commands.
    public static let homebrewBinaries = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// The System Settings pane that grants the privilege.
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools"

    /// The log message naming the files and both fixes.
    public static func warning(for files: [String]) -> String {
        "Gatekeeper will kill these agent helpers when AgentIDE starts them: Homebrew left them quarantined "
            + "and AgentIDE lacks the Developer Tools privilege, so Codex reports its shell host exiting during "
            + "startup. Add AgentIDE under System Settings, Privacy & Security, Developer Tools, "
            + "or clear the attribute in Terminal:\n\n  xattr -d com.apple.quarantine "
            + files.map(\.shellQuoted).joined(separator: " ")
    }

    /// The quarantined files among the agents' installs that this
    /// app cannot run: empty when every install is clean, and empty
    /// when AgentIDE holds the privilege, which a quarantined script
    /// of its own proves by surviving. The probe runs only once
    /// something is quarantined, so a clean machine never pays for it.
    public func blockedFiles() async -> [String] {
        let quarantined = AgentKind.allCases.flatMap(quarantinedFiles(for:))
        guard quarantined.isEmpty == false, await probeIsKilled() else {
            return []
        }

        return quarantined
    }

    // MARK: Private

    private static let quarantineAttribute = "com.apple.quarantine"

    /// The shell's status for a child the kernel killed.
    private static let killedStatus = "137"

    private let runner: any ProcessRunner
    private let binaryDirectories: [String]

    private static func isQuarantined(_ path: String) -> Bool {
        getxattr(path, quarantineAttribute, nil, 0, 0, 0) >= 0
    }

    /// Every quarantined file beside the agent's real binary: a
    /// cask's `bin` holds the helpers the agent launches, and any of
    /// them is the one that dies.
    private func quarantinedFiles(for agent: AgentKind) -> [String] {
        for directory in binaryDirectories {
            let link = directory + "/" + agent.rawValue
            guard FileManager.default.fileExists(atPath: link) else {
                continue
            }

            let install = URL(filePath: link).resolvingSymlinksInPath().deletingLastPathComponent()
            let files = try? FileManager.default.contentsOfDirectory(at: install, includingPropertiesForKeys: nil)
            return (files ?? []).map(\.path).filter(Self.isQuarantined).sorted()
        }
        return []
    }

    /// Runs a freshly quarantined script the way the app runs
    /// everything; Gatekeeper kills it at exec exactly when it would
    /// kill an agent's helper.
    private func probeIsKilled() async -> Bool {
        let probe = FileManager.default.temporaryDirectory.appending(path: "agentide-gatekeeper-" + UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: probe)
        }
        do {
            try "#!/bin/sh\nexit 0\n".write(to: probe, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        let marker = "0083;00000000;AgentIDE;"
        let marked = marker.withCString { value in
            setxattr(probe.path, Self.quarantineAttribute, value, marker.utf8.count, 0, 0) == 0
        }
        guard marked, chmod(probe.path, 0o755) == 0 else {
            return false
        }

        let result = try? await runner.run(
            ["/bin/zsh", "-c", probe.path.shellQuoted + " </dev/null; echo $?"],
            workingDirectory: nil,
            environment: [:],
        )
        return result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == Self.killedStatus
    }
}
