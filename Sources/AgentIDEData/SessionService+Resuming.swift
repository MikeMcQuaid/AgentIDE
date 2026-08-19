import AgentIDEDomain
import Foundation

/// Getting an agent running again in a worktree. Resuming fails in
/// ways that look like success: the agent starts, refuses the
/// conversation it was handed and exits, and tmux keeps the dead
/// pane, so the name is taken and the terminal attaches to a corpse.
/// Every way in therefore replaces whatever holds the name and is
/// checked for still being alive a moment later.
extension SessionService {
    /// Starts a session under a name, trying each command in turn
    /// until one is still running, and killing whatever holds the
    /// name before each attempt. Throws when none of them stayed up.
    func start(sessionName: String, directory: String, trying commands: [String]) async throws {
        var failure: (any Error)?
        for command in commands {
            await killTmuxSession(name: sessionName, isHostShell: false)
            do {
                try await tmux.newSession(name: sessionName, directory: directory, command: command)
            } catch {
                failure = error
                continue
            }
            if await isRunning(sessionName: sessionName) {
                return
            }
        }
        throw failure ?? CommandError(
            command: commands.last ?? sessionName,
            result: ProcessResult(
                status: 1,
                standardOutput: "",
                standardError: "The agent exited as soon as it started",
            ),
        )
    }

    /// The ways to continue a worktree's own agent, best first: the
    /// conversation recorded for it, then the conversations its
    /// transcripts still name, then a fresh one. Relaunching with
    /// the original prompt is deliberately not among them: it would
    /// re-run the whole task against an already changed worktree.
    func resumeCommands(sessionName: String, agent: AgentKind, worktreePath: String) -> [String] {
        let metadata = store.load()
        let arguments = metadata.arguments[sessionName] ?? ""
        let agentRunner = runner(for: agent)
        var commands = [String]()
        if let resumeID = metadata.resumeIDs[sessionName] {
            commands.append(agentRunner.resumeCommand(resumeID: resumeID, extraArguments: arguments))
        }
        let past = sessionsInDirectories(of: worktreePath, liveSession: nil)
            .filter { $0.agent == agent }
            .prefix(Self.transcriptAttempts)
            .map { agentRunner.resumeCommand(resumeID: $0.resumeID, extraArguments: arguments) }
        commands += past.filter { commands.contains($0) == false }
        commands.append(agentRunner.launchCommand(extraArguments: arguments, promptFile: nil))
        return commands
    }

    // MARK: Private

    /// How many recorded conversations to offer the agent before
    /// giving up on continuing one: the newest few are the ones a
    /// resume plausibly means.
    private static let transcriptAttempts = 3

    /// How long a session has to survive to count as started, as
    /// polls: an agent that refuses its conversation exits at once,
    /// well inside this.
    private static let livenessPolls = 4
    private static let livenessPollMilliseconds = 350

    /// Whether the session is still there with a live pane shortly
    /// after starting.
    private func isRunning(sessionName: String) async -> Bool {
        for _ in 0 ..< Self.livenessPolls {
            try? await Task.sleep(for: .milliseconds(Self.livenessPollMilliseconds))
            let panes = await (try? tmux.panes()) ?? []
            guard let pane = panes.first(where: { $0.sessionName == sessionName }) else {
                return false
            }
            guard pane.isDead == false else {
                return false
            }
        }
        return true
    }
}
