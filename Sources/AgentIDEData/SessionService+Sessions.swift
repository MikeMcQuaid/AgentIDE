import AgentIDEDomain
import Foundation

/// Watching, closing and resuming individual sessions.
public extension SessionService {
    /// The displayable conversation log of a past session.
    func transcriptEntries(for past: TranscriptSession) -> [TranscriptEntry] {
        transcripts.entries(in: URL(fileURLWithPath: past.path))
    }

    /// Pushes the branch and opens a pull request; returns its URL.
    func pushAndCreatePullRequest(worktree: Worktree) async throws -> String {
        try await git.push(worktreePath: worktree.path, branch: worktree.branch)
        let title = try await git.lastCommitMessage(worktreePath: worktree.path)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        return try await github.createPullRequest(worktreePath: worktree.path, title: title)
    }

    /// The argv that attaches a terminal to a session.
    func attachCommand(sessionName: String) -> [String] {
        tmux.attachCommand(sessionName: sessionName)
    }

    /// The argv for a persistent host-user shell in a worktree: a
    /// host tmux session (attach-or-create) that survives tab
    /// switches and app restarts and starts the user's default login
    /// shell. Named `agentide-shell--<repository>--<branch>`, so
    /// `tmux ls` reads like the sidebar rather than worktree uuids.
    /// The chained `set` commands give the host server the same
    /// wheel-scrolls-history behaviour as the sandbox one, whose
    /// config file it does not read.
    func hostShellCommand(worktree: Worktree) -> [String] {
        let name = "agentide-shell--"
            + SessionName.slug(worktree.repositoryName) + "--"
            + SessionName.slug(worktree.branch)
        return [
            Self.hostTmuxPath, "new-session", "-A", "-s", name, "-c", worktree.path,
            ";", "set", "-g", "mouse", "on",
            ";", "set", "-g", "history-limit", "50000",
            ";", "set", "-g", "default-terminal", "xterm-256color",
            ";", "set", "-g", "status", "off",
        ]
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
            .filter { $0.hasPrefix("agentide-shell--") }
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
    /// survive so it stays resumable.
    func closeSession(sessionName: String, worktreePath: String) async throws {
        rememberResumeID(sessionName: sessionName, worktreePath: worktreePath)
        try await tmux.killSession(name: sessionName)
    }

    /// Resumes the session last launched in a worktree, whether or not
    /// a live tmux session still names it.
    func resumeWorktree(_ worktree: Worktree) async throws {
        guard let sessionName = store.load().sessionsByWorktree[worktree.path] else {
            throw CommandError(
                command: "resume " + worktree.path,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "No session recorded here yet"),
            )
        }

        try await resumeSession(sessionName: sessionName, worktree: worktree)
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

    /// Relaunches a closed session's conversation in its worktree.
    func resumeSession(sessionName: String, worktree: Worktree) async throws {
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
            let command = runner(for: agent).launchCommand(extraArguments: arguments)
            try await tmux.newSession(name: sessionName, directory: worktree.path, command: command)
            let promptFile = paths.promptsDirectory + "/" + sessionName + ".md"
            if FileManager.default.fileExists(atPath: promptFile) {
                try await tmux.sendPromptFile(promptFile, to: sessionName)
            }
        }
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
        runners
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
        store.save(metadata)
    }
}
