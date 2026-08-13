import AgentIDEDomain
import Foundation

/// The terminal panes' scrollback and wheel routing, for both the
/// sandboxed agent sessions and the host shells.
public extension SessionService {
    /// Commands whose wheel events should scroll the command itself
    /// (as arrow keys) rather than open the scrollback viewer.
    internal static let pagerCommands: Set<String> = [
        "less", "more", "most", "delta", "bat", "man", "pspg",
    ]

    /// An agent session's whole pane text, scrollback included.
    func captureAgentPane(sessionName: String) async -> String {
        await tmux.capturePane(sessionName: sessionName)
    }

    /// Whether the agent session is showing a pager right now.
    func agentPaneIsPaging(sessionName: String) async -> Bool {
        guard let command = await tmux.currentCommand(sessionName: sessionName) else {
            return false
        }

        return Self.pagerCommands.contains(command)
    }

    /// A host shell's whole pane text, scrollback included.
    func captureHostShell(worktree: Worktree) async -> String {
        let result = try? await processes.run(
            [
                Self.hostTmuxPath, "capture-pane", "-p", "-J", "-S", "-50000",
                "-t", hostShellName(worktree: worktree),
            ],
            workingDirectory: nil,
            environment: [:],
        )
        guard let result, result.succeeded else {
            return ""
        }

        return result.standardOutput
    }

    /// Whether the host shell is showing a pager right now.
    func hostShellIsPaging(worktree: Worktree) async -> Bool {
        let result = try? await processes.run(
            [
                Self.hostTmuxPath, "display-message", "-p",
                "-t", hostShellName(worktree: worktree), "#{pane_current_command}",
            ],
            workingDirectory: nil,
            environment: [:],
        )
        guard let result, result.succeeded else {
            return false
        }

        let command = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.pagerCommands.contains(command)
    }
}
