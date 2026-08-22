import AgentIDEDomain
import Foundation

/// Getting an agent running again in a worktree. Resuming fails in
/// ways that look like success: the agent starts, refuses the
/// conversation it was handed and exits back to its pane's shell,
/// so the label is taken and the terminal attaches to an empty
/// prompt. Every way in therefore replaces whatever holds the label
/// and is checked for still being alive a moment later.
extension SessionService {
    /// Starts a session under a name, trying each command in turn
    /// until one is still running, and killing whatever holds the
    /// name before each attempt. Throws when none of them stayed up.
    func start(sessionName: String, directory: String, trying commands: [String]) async throws {
        var failure: (any Error)?
        for command in commands {
            await progress("Trying: " + command.prefix(Self.commandPreview))
            do {
                try await startFresh(sessionName: sessionName, directory: directory, command: command)
            } catch {
                failure = error
                continue
            }
            await progress("Checking the agent is still running")
            if await isRunning(sessionName: sessionName) {
                await awaitReady(sessionName: sessionName)
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

    /// Waits until herdr detects the launched agent's interface, so
    /// the page narrating the launch stays until the agent is there
    /// to take input, rather than switching to a pane that is still
    /// booting. A pane running something herdr could never recognise
    /// as an agent has nothing to wait for, and a detection that
    /// never comes stops the wait after a minute rather than forever.
    func awaitReady(sessionName: String) async {
        await progress("Waiting for the agent's interface to come up")
        let agents = AgentKind.allCases.map(\.rawValue)
        for _ in 0 ..< Self.readyPolls {
            let panes = await (try? herdr.panes()) ?? []
            guard let pane = panes.first(where: { $0.sessionName == sessionName }) else {
                return
            }

            let unrecognisable = pane.foregroundCommand.map { agents.contains($0) == false } ?? false
            if pane.isFinished || pane.activity != nil || unrecognisable {
                return
            }

            try? await Task.sleep(for: .seconds(Self.readyPollSeconds))
        }
    }

    /// Copies a worktree's newest conversation somewhere the sandbox
    /// cannot reach, and says where it went. Called wherever a
    /// conversation is about to be relied on or left behind, since
    /// those are the moments it is worth having a copy of.
    func backUpConversation(of worktree: Worktree) {
        guard let newest = sessionsInDirectories(of: worktree.path, liveSession: nil).first else {
            return
        }

        ConversationBackup(paths: paths).store(newest, worktree: worktree)
    }

    /// Copies the conversation of every worktree with a running
    /// session, at most once an hour each and only when the
    /// transcript has moved on. A session can run for a day between
    /// being started and being closed, and a copy taken only at
    /// those two moments would be a day stale when the sandbox went
    /// away. Off the caller's actor: this reads and copies files
    /// while the window is being used.
    @concurrent
    func backUpRunningConversations(_ groups: [RepositoryGroup]) async {
        var metadata = store.load()
        var copied = false
        let now = Date()
        for item in groups.flatMap(\.items) where item.session?.status == .running {
            let last = metadata.conversationBackupAt[item.worktree.path] ?? .distantPast
            guard now.timeIntervalSince(last) >= Self.backupIntervalSeconds else {
                continue
            }

            backUpConversation(of: item.worktree)
            metadata.conversationBackupAt[item.worktree.path] = now
            copied = true
        }
        guard copied else {
            return
        }

        store.save(metadata)
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

    /// How often a running session's conversation is copied: often
    /// enough that little is lost, rarely enough that copying a long
    /// transcript is never in anyone's way.
    private static let backupIntervalSeconds = 3_600.0

    /// How much of a command a narrated step shows; the prompt
    /// rides inside the command and can be long.
    private static let commandPreview = 120

    /// How long to wait for the agent's interface before giving up
    /// on detection and showing the pane anyway.
    private static let readyPolls = 60
    private static let readyPollSeconds = 1.0

    /// How many recorded conversations to offer the agent before
    /// giving up on continuing one: the newest few are the ones a
    /// resume plausibly means.
    private static let transcriptAttempts = 3

    /// How long a session has to survive to count as started, as
    /// polls: an agent that refuses its conversation exits at once,
    /// well inside this.
    private static let livenessPolls = 4
    private static let livenessPollMilliseconds = 350

    /// Whether the session is still there with its agent running
    /// shortly after starting. Only an answered listing can fail the
    /// check: a herdr hiccup answers nothing, and declaring a live
    /// agent dead over one had the retry killing it mid-start.
    private func isRunning(sessionName: String) async -> Bool {
        for _ in 0 ..< Self.livenessPolls {
            try? await Task.sleep(for: .milliseconds(Self.livenessPollMilliseconds))
            guard let panes = try? await herdr.panes() else {
                continue
            }
            guard let pane = panes.first(where: { $0.sessionName == sessionName }) else {
                return false
            }
            guard pane.isFinished == false else {
                return false
            }
        }
        return true
    }
}
