import AgentIDEDomain
import Foundation

/// Watching, closing and resuming individual sessions.
public extension SessionService {
    /// Host shells share the host tmux server across flavours, so
    /// dev builds and tests get their own name prefix and can never
    /// list or kill production shells.
    internal static let hostShellPrefix = WorkspacePaths.isProductionBuild
        ? "agentide-shell--"
        : "agentide-shell-dev--"

    /// The host's tmux binary; Homebrew's location is not on a GUI
    /// app's default PATH.
    internal static var hostTmuxPath: String {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
    }

    /// The displayable conversation log of a past session.
    func transcriptEntries(for past: TranscriptSession) -> [TranscriptEntry] {
        transcripts.entries(in: URL(fileURLWithPath: past.path))
    }

    /// The argv that attaches a terminal to a session.
    func attachCommand(sessionName: String) -> [String] {
        tmux.attachCommand(sessionName: sessionName)
    }

    /// The argv for a persistent host-user shell in a worktree: a
    /// host tmux session (attach-or-create) that survives tab
    /// switches and app restarts and starts the user's default login
    /// shell. Named `agentide-shell--<repository>-<digest>--<branch>`
    /// so `tmux ls` reads like the sidebar rather than worktree
    /// uuids; the path digest keeps same-named repositories under
    /// different owners from attaching to each other's shells.
    /// The chained `set` commands give the host server the same
    /// wheel-scrolls-history behaviour as the sandbox one, whose
    /// config file it does not read.
    func hostShellCommand(worktree: Worktree) -> [String] {
        let name = Self.hostShellPrefix
            + SessionName.slug(worktree.repositoryName) + "-"
            + SessionName.pathDigest(worktree.repositoryPath) + "--"
            + SessionName.slug(worktree.branch)
        // The config applies at server birth, before the first
        // client connects and computes its terminal features; the
        // chained commands repeat the options because a long-running
        // server never rereads config. `-f` also keeps the user's
        // own tmux config out of these app-managed sessions.
        return [
            Self.hostTmuxPath, "-f", hostTmuxConfigFile(),
            "new-session", "-A", "-s", name, "-c", worktree.path,
            ";", "set", "-g", "mouse", "on",
            ";", "set", "-g", "history-limit", "50000",
            ";", "set", "-g", "default-terminal", "xterm-256color",
            ";", "set", "-g", "status", "off",
            ";", "set", "-s", "set-clipboard", "on",
            ";", "set", "-as", "terminal-features", "xterm-256color:clipboard",
            ";", "bind", "-T", "copy-mode", "MouseDragEnd1Pane", "send-keys", "-X", "copy-selection",
            ";", "bind", "-T", "copy-mode-vi", "MouseDragEnd1Pane", "send-keys", "-X", "copy-selection",
        ]
    }

    /// Writes the host shell server's config beside the app's other
    /// state and returns its path; matching the sandbox server's
    /// copy behaviour, present from the server's first moment.
    private func hostTmuxConfigFile() -> String {
        let directory = NSHomeDirectory() + "/Library/Application Support/AgentIDE"
        let file = directory + "/host-tmux.conf"
        let content = """
        set -g mouse on
        set -g history-limit 50000
        set -g default-terminal xterm-256color
        set -g status off
        set -s set-clipboard on
        set -as terminal-features xterm-256color:clipboard
        bind -T copy-mode MouseDragEnd1Pane send-keys -X copy-selection
        bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection
        """
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? content.write(toFile: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Every AgentIDE tmux session for the session manager: the
    /// sandboxed agents and the host shells, deduplicated.
    func allTmuxSessions() async -> [(name: String, isHostShell: Bool)] {
        var seen = Set<String>()
        var results = [(name: String, isHostShell: Bool)]()
        for pane in await (try? tmux.panes()) ?? [] where seen.insert(pane.sessionName).inserted {
            results.append((pane.sessionName, false))
        }
        let list = try? await processes.run(
            [Self.hostTmuxPath, "ls", "-F", "#{session_name}"],
            workingDirectory: nil,
            environment: [:],
        )
        let shells = (list?.standardOutput ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix(Self.hostShellPrefix) }
        for name in shells where seen.insert(name).inserted {
            results.append((name, true))
        }
        return results
    }

    /// Kills one session on whichever server owns it.
    func killTmuxSession(name: String, isHostShell: Bool) async {
        if isHostShell {
            _ = try? await processes.run(
                [Self.hostTmuxPath, "kill-session", "-t", name],
                workingDirectory: nil,
                environment: [:],
            )
        } else {
            try? await tmux.killSession(name: name)
        }
    }

    /// Marks a worktree viewed: clears its unread state, including a
    /// manual mark.
    func markSeen(worktreePath: String) {
        var metadata = store.load()
        metadata.seenAt[worktreePath] = Date()
        metadata.unreadMarks.removeAll { $0 == worktreePath }
        store.save(metadata)
    }

    /// Records that the worktree's current activity has been seen
    /// without clearing a manual unread mark, for the selected item
    /// staying on screen.
    func acknowledgeActivity(worktreePath: String) {
        var metadata = store.load()
        metadata.seenAt[worktreePath] = Date()
        store.save(metadata)
    }

    /// Flags a worktree unread until it is next viewed.
    func markUnread(worktreePath: String) {
        var metadata = store.load()
        if metadata.unreadMarks.contains(worktreePath) == false {
            metadata.unreadMarks.append(worktreePath)
        }
        store.save(metadata)
    }

    /// Commits anything the agent left uncommitted.
    func commitOutstanding(worktreePath: String) async throws {
        guard await git.isDirty(worktreePath: worktreePath) else {
            return
        }

        try await git.commitAll(worktreePath: worktreePath, message: "Commit outstanding agent work")
    }

    /// Kills the tmux session; worktree, transcript and metadata
    /// survive so it stays resumable. The deliberate close is
    /// recorded so automatic resumes leave this worktree alone.
    func closeSession(sessionName: String, worktreePath: String) async throws {
        rememberResumeID(sessionName: sessionName, worktreePath: worktreePath)
        var metadata = store.load()
        if metadata.intentionallyClosed.contains(worktreePath) == false {
            metadata.intentionallyClosed.append(worktreePath)
        }
        store.save(metadata)
        try await tmux.killSession(name: sessionName)
    }

    /// Whether the worktree's last session ended by explicit close,
    /// so automatic resumes skip it.
    func wasIntentionallyClosed(worktreePath: String) -> Bool {
        store.load().intentionallyClosed.contains(worktreePath)
    }

    /// A session starting or resuming clears the deliberate-close
    /// mark, so automatic resumes apply again afterwards.
    internal func clearIntentionalClose(worktreePath: String) {
        var metadata = store.load()
        metadata.intentionallyClosed.removeAll { $0 == worktreePath }
        store.save(metadata)
    }

    /// Whether a closed session is recorded for a worktree, so panes
    /// can offer resuming even when no transcript lists under it.
    func hasRecordedSession(worktreePath: String) -> Bool {
        store.load().sessionsByWorktree[worktreePath] != nil
    }

    /// Deletes a past conversation's transcript, removing it from
    /// every listing; only an explicit user action calls this.
    /// Transcripts belong to the sandbox user and the host user can
    /// only read them, so when a direct removal is refused the
    /// deletion runs again as their owner through the launcher.
    func deleteConversation(_ past: TranscriptSession) async throws {
        if (try? FileManager.default.removeItem(atPath: past.path)) != nil {
            return
        }

        let quoted = "'" + past.path.replacing("'", with: "'\\''") + "'"
        let launcher = SandvaultLauncher(hostUser: paths.hostUser)
        let command = launcher.command(
            payload: "rm -f " + quoted,
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-delete",
        )
        let result = try await processes.run(command, workingDirectory: nil, environment: [:])
        guard result.succeeded else {
            throw CommandError(command: "rm -f " + past.path, result: result)
        }
    }

    /// Copies a dropped file into the shared workspace, where the
    /// sandboxed agent can read it, returning the staged path.
    func stageDroppedFile(at url: URL) throws -> String {
        let directory = paths.sharedWorkspace + "/tmp"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let destination = directory + "/drop-" + UUID().uuidString + "-" + url.lastPathComponent
        try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destination))
        return destination
    }

    /// Types text into a session's terminal, as pasted input.
    func typeText(_ text: String, sessionName: String) async throws {
        try await tmux.typeText(text, sessionName: sessionName)
    }

    /// Resumes the session last recorded in a worktree, whether or
    /// not a live tmux session still names it.
    func resumeWorktree(_ worktree: Worktree) async throws {
        guard let sessionName = store.load().sessionsByWorktree[worktree.path] else {
            throw CommandError(
                command: "resume " + worktree.path,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "No session recorded here yet"),
            )
        }
        guard let agent = agentKind(of: sessionName) else {
            throw CommandError(
                command: "resume " + sessionName,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "Unknown agent in session name"),
            )
        }

        let metadata = store.load()
        let arguments = metadata.arguments[sessionName] ?? ""
        if let resumeID = metadata.resumeIDs[sessionName] {
            let command = runner(for: agent).resumeCommand(resumeID: resumeID, extraArguments: arguments)
            try await tmux.newSession(name: sessionName, directory: worktree.path, command: command)
        } else {
            let promptFile = paths.promptsDirectory + "/" + sessionName + ".md"
            let existing = FileManager.default.fileExists(atPath: promptFile) ? promptFile : nil
            let command = runner(for: agent).launchCommand(extraArguments: arguments, promptFile: existing)
            try await tmux.newSession(name: sessionName, directory: worktree.path, command: command)
        }
        clearIntentionalClose(worktreePath: worktree.path)
    }

    /// Relaunches a past conversation in its own worktree, replacing
    /// any session already there.
    func resumePast(_ past: TranscriptSession, worktree: Worktree) async throws -> String {
        let sessionName = SessionName.make(
            repository: worktree.repositoryName,
            branch: worktree.branch,
            agent: past.agent,
        )
        try? await tmux.killSession(name: sessionName)
        try await tmux.newSession(
            name: sessionName,
            directory: worktree.path,
            command: runner(for: past.agent).resumeCommand(resumeID: past.id, extraArguments: ""),
        )
        remember(sessionName: sessionName, worktreePath: worktree.path, resumeID: past.id)
        return sessionName
    }

    /// Creates a fresh worktree and branch and resumes a past
    /// conversation there. The transcript is copied into the new
    /// working directory's transcript directory first, because agents
    /// look sessions up by working directory.
    func resumeInNewWorktree(_ past: TranscriptSession, repository: Repository) async throws -> String {
        let seed = past.title.isEmpty ? past.id : past.title
        let branch = await availableBranch(repository: repository, prompt: "resume " + seed)
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let sessionName = SessionName.make(repository: repository.name, branch: branch, agent: past.agent)
        addFriendlySymlink(repository: repository, branch: branch, worktreePath: worktreePath)

        let agentRunner = runner(for: past.agent)
        copyTranscript(past, intoWorktree: worktreePath, using: agentRunner)
        try await tmux.newSession(
            name: sessionName,
            directory: worktreePath,
            command: agentRunner.resumeCommand(resumeID: past.id, extraArguments: ""),
        )
        remember(sessionName: sessionName, worktreePath: worktreePath, resumeID: past.id)
        return sessionName
    }

    // MARK: Internal

    /// Earlier conversations for a worktree, newest first, from every
    /// runner with per-directory transcripts. A live session's own
    /// transcript is its directory's newest, so that one is skipped.
    /// The repository's main checkout also collects conversations
    /// orphaned by deleted worktrees, so they stay readable and
    /// resumable.
    func pastSessions(of worktree: Worktree, liveSession: AgentSession?) -> [TranscriptSession] {
        var sessions = sessionsInDirectories(of: worktree.path, liveSession: liveSession)
        if worktree.path == worktree.repositoryPath {
            sessions += orphanedSessions(repositoryName: worktree.repositoryName)
        }
        return sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Private

    internal func sessionsInDirectories(
        of workingDirectory: String,
        liveSession: AgentSession?,
    ) -> [TranscriptSession] {
        let scoped = runners
            .filter(\.scopesTranscriptsByWorkingDirectory)
            .flatMap { runner -> [TranscriptSession] in
                guard let directory = runner.transcriptDirectory(
                    workingDirectory: workingDirectory,
                    sandboxHome: paths.sandboxHome,
                ) else {
                    return []
                }

                let sessions = transcripts.sessions(in: directory, agent: runner.kind)
                let hidesNewest = liveSession?.agent == runner.kind
                return hidesNewest ? Array(sessions.dropFirst()) : sessions
            }
        // Codex keeps one flat date tree with the working directory
        // embedded per session, so its conversations come from the
        // index rather than a per-worktree directory.
        let codex = codexIndex.sessions(
            inRoot: paths.sandboxHome + "/.codex/sessions",
            workingDirectory: workingDirectory,
        )
        let hidesNewestCodex = liveSession?.agent == .codexCLI
        return scoped + (hidesNewestCodex ? Array(codex.dropFirst()) : codex)
    }

    /// Conversations whose worktree no longer exists, attributed to
    /// the repository through the session names recorded at launch.
    private func orphanedSessions(repositoryName: String) -> [TranscriptSession] {
        let slug = SessionName.slug(repositoryName)
        return store.load()
            .sessionsByWorktree
            .filter { path, sessionName in
                SessionName.repositorySlug(of: sessionName) == slug
                    && FileManager.default.fileExists(atPath: path) == false
            }
            .flatMap { path, _ in
                sessionsInDirectories(of: path, liveSession: nil)
            }
    }

    // MARK: Private

    private func copyTranscript(
        _ past: TranscriptSession,
        intoWorktree worktreePath: String,
        using agentRunner: any AgentRunner,
    ) {
        guard agentRunner.scopesTranscriptsByWorkingDirectory,
              let directory = agentRunner.transcriptDirectory(
                  workingDirectory: worktreePath,
                  sandboxHome: paths.sandboxHome,
              )
        else {
            return
        }

        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: past.path, toPath: directory + "/" + past.id + ".jsonl")
    }

    private func remember(sessionName: String, worktreePath: String, resumeID: String) {
        var metadata = store.load()
        metadata.resumeIDs[sessionName] = resumeID
        metadata.sessionsByWorktree[worktreePath] = sessionName
        metadata.seenAt[worktreePath] = Date()
        metadata.intentionallyClosed.removeAll { $0 == worktreePath }
        store.save(metadata)
    }
}
