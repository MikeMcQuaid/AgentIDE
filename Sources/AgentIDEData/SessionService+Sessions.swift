import AgentIDEDomain
import Foundation

/// How long a closed workspace gets to go before the close is
/// asked again.
private let killGraceSeconds = 0.5

/// Watching, closing and resuming individual sessions.
public extension SessionService {
    /// The displayable conversation log of a past session.
    func transcriptEntries(for past: TranscriptSession) -> [TranscriptEntry] {
        transcripts.entries(in: URL(fileURLWithPath: past.path))
    }

    /// The argv that attaches a terminal to a session's pane.
    func attachCommand(paneID: String) -> [String] {
        herdr.attachCommand(paneID: paneID)
    }

    /// Kills one session's workspace, which kills the process tree
    /// inside it, and asks again after a grace period when the
    /// close does not take: the host cannot signal another user's
    /// processes and the sudoers rules stay narrow, so herdr is the
    /// only lever.
    func killSession(name: String) async {
        // A name nothing holds is the common case on a fresh start,
        // and confirming it costs a listing of every pane, so only a
        // kill that answered "nothing was there" skips the check. A
        // kill that closed something, or failed part way and cannot
        // say, is checked and retried.
        let closed = await (try? herdr.killSession(name: name))
        guard closed != 0, await sessionExists(name: name) else {
            return
        }

        try? await Task.sleep(for: .seconds(killGraceSeconds))
        try? await herdr.killSession(name: name)
    }

    /// Starts a session under a name, replacing whatever holds it
    /// rather than joining in. herdr is how sessions survive the app
    /// quitting, crashing or updating; it is not how an agent
    /// survives its own upgrade, since an agent still running from a
    /// version whose files have been deleted fails in ways that read
    /// as the app's fault. Anything the user asks for by hand comes
    /// through here and gets a new process.
    internal func startFresh(
        sessionName: String,
        directory: String,
        command: String,
        probed version: String? = nil,
    ) async throws {
        // The agent about to start reads the terminal's colours once
        // and trusts them forever; remember which appearance it is
        // being born into, so the pane can keep its word.
        rememberTerminalScheme(worktreePath: directory)
        await progress("Closing any previous session")
        await killSession(name: sessionName)
        if let agent = agentKind(of: sessionName) {
            await clearQuarantine(for: agent)
        }
        // The version probe finishes before the launch, never runs
        // beside it: it is a second copy of the same CLI, and Codex
        // stages its execution host under a lock in its own home,
        // which two copies starting at once contend for. Creation
        // hands one already running alongside the worktree, which is
        // where the seconds it costs are free.
        if let version {
            record(version: version, sessionName: sessionName)
        } else if store.load().agentVersions[sessionName] == nil {
            // A resume already knows: the first launch recorded the
            // version, and asking again is a sandbox launch of the
            // CLI that cost seconds on every resume for a fact that
            // only changes when the CLI is upgraded, which a fresh
            // creation catches. Only a name never launched asks.
            await progress("Asking the agent's CLI its version")
            await recordAgentVersion(sessionName: sessionName)
        }
        try await herdr.newSession(name: sessionName, directory: directory, command: command)
    }

    /// Asks the agent's CLI what version it is and remembers it
    /// under the session name, so the pane says which version it is
    /// running rather than which one is installed now: a session
    /// that outlived an upgrade is the one worth spotting.
    internal func recordAgentVersion(sessionName: String) async {
        guard let agent = agentKind(of: sessionName) else {
            return
        }

        await record(version: probeVersion(of: agent), sessionName: sessionName)
    }

    /// Asks a CLI its version. The same install answers from the
    /// host, since Homebrew's prefix is one place for both users, and
    /// asking there skips the sudo, environment scrub and
    /// sandbox-exec a sandbox launch wraps around one line of output.
    /// Only when no host copy answers does the sandbox get asked.
    func probeVersion(of agent: AgentKind) async -> String? {
        let parse = runner(for: agent).parseVersion
        for prefix in Quarantine.homebrewBinaries {
            let binary = prefix + "/" + agent.rawValue
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                continue
            }

            let result = try? await processes.run([binary, "--version"], workingDirectory: nil, environment: [:])
            if let version = parse(result?.standardOutput ?? "") {
                return version
            }
        }
        let argv = launcher.command(
            payload: agent.rawValue + " --version </dev/null",
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-version",
        )
        let result = try? await processes.run(argv, workingDirectory: nil, environment: [:])
        return parse(result?.standardOutput ?? "")
    }

    /// Remembers a probed version under the session name, so the
    /// pane says which version it is running rather than which one
    /// is installed now.
    internal func record(version: String?, sessionName: String) {
        guard let version else {
            return
        }

        store.update { metadata in
            metadata.agentVersions[sessionName] = version
        }
    }

    /// Marks a worktree viewed: clears its unread state, including a
    /// manual mark.
    func markSeen(worktreePath: String) {
        store.update { metadata in
            metadata.seenAt[worktreePath] = Date()
            metadata.unreadMarks.removeAll { $0 == worktreePath }
        }
    }

    /// Records that the worktree's current activity has been seen
    /// without clearing a manual unread mark, for the selected item
    /// staying on screen.
    func acknowledgeActivity(worktreePath: String) {
        store.update { metadata in
            metadata.seenAt[worktreePath] = Date()
        }
    }

    /// Flags a worktree unread until it is next viewed.
    func markUnread(worktreePath: String) {
        store.update { metadata in
            if metadata.unreadMarks.contains(worktreePath) == false {
                metadata.unreadMarks.append(worktreePath)
            }
        }
    }

    /// Commits anything the agent left uncommitted.
    func commitOutstanding(worktreePath: String) async throws {
        guard await git.isDirty(worktreePath: worktreePath) else {
            return
        }

        try await git.commitAll(worktreePath: worktreePath, message: "Commit outstanding agent work")
    }

    /// Ends the session's workspace and everything in it, asking
    /// again when the polite close does not take; worktree,
    /// transcript and metadata survive so it stays resumable. The
    /// deliberate close is recorded so automatic resumes leave this
    /// worktree alone.
    func closeSession(sessionName: String, worktree: Worktree) async {
        // The conversation is copied before the session goes, since
        // a close is one of the two moments it is worth keeping.
        backUpConversation(of: worktree)
        let worktreePath = worktree.path
        rememberResumeID(sessionName: sessionName, worktreePath: worktreePath)
        store.update { metadata in
            if metadata.intentionallyClosed.contains(worktreePath) == false {
                metadata.intentionallyClosed.append(worktreePath)
            }
        }
        await killSession(name: sessionName)
    }

    /// Whether a live herdr pane holds this worktree's session: one
    /// pane listing, which is all a resume needs to know before
    /// launching, where a whole overview read every worktree's git.
    func hasLiveSession(worktreePath: String) async -> Bool {
        let recorded = store.load().sessionsByWorktree[worktreePath]
        let panes = await (try? herdr.panes()) ?? []
        return panes.contains { pane in
            SessionName.isAgentIDE(pane.sessionName) && pane.isFinished == false
                && (pane.sessionName == recorded || pane.currentPath == worktreePath)
        }
    }

    /// Whether the worktree's last session ended by explicit close,
    /// so automatic resumes skip it.
    func wasIntentionallyClosed(worktreePath: String) -> Bool {
        store.load().intentionallyClosed.contains(worktreePath)
    }

    /// A session starting or resuming clears the deliberate-close
    /// mark, so automatic resumes apply again afterwards.
    internal func clearIntentionalClose(worktreePath: String) {
        store.update { metadata in
            metadata.intentionallyClosed.removeAll { $0 == worktreePath }
        }
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

        let launcher = SandvaultLauncher(hostUser: paths.hostUser)
        let command = launcher.command(
            payload: "rm -f " + past.path.shellQuoted,
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
        try await herdr.typeText(text, sessionName: sessionName)
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
}
