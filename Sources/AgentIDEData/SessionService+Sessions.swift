import AgentIDEDomain
import Foundation

/// Watching, closing and resuming individual sessions.
public extension SessionService {
    /// Marks a session's output as read.
    func markSeen(sessionName: String) {
        var metadata = store.load()
        metadata.lastSeen[sessionName] = Date()
        store.save(metadata)
    }

    /// The last assistant message of the session's newest transcript.
    func finalMessage(session: AgentSession, worktreePath: String) -> String? {
        guard let agent = session.agent,
              let directory = runner(for: agent).transcriptDirectory(
                  workingDirectory: worktreePath,
                  sandboxHome: paths.sandboxHome,
              ),
              let transcript = transcripts.latestTranscript(in: directory)
        else {
            return nil
        }

        return transcripts.finalAssistantMessage(in: transcript)
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
}
