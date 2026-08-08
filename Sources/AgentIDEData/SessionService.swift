import AgentIDEDomain
import Foundation

/// Orchestrates the core loop: worktrees, sessions, review actions
/// and lifecycle. Feature models call this; it composes the clients.
/// Lifecycle (archive, undelete) lives in its own extension file.
public struct SessionService: Sendable {
    // MARK: Lifecycle

    /// Creates the service.
    public init(
        paths: WorkspacePaths,
        git: GitClient,
        tmux: TmuxClient,
        github: GitHubClient,
        transcripts: TranscriptReader,
        spool: EventSpool,
        store: MetadataStore,
        runners: [any AgentRunner],
    ) {
        self.paths = paths
        self.git = git
        self.tmux = tmux
        self.github = github
        self.transcripts = transcripts
        self.spool = spool
        self.store = store
        self.runners = runners
    }

    // MARK: Public

    /// The repositories in the shared workspace.
    public func repositories() -> [Repository] {
        git.repositories(under: paths.repositoriesDirectory)
    }

    /// The full dashboard state: every repository's worktrees joined
    /// with their sessions, plus foreign sessions.
    public func overview() async -> (groups: [RepositoryGroup], foreign: [AgentSession]) {
        let panes = await (try? tmux.panes()) ?? []
        let activity = spool.activity()
        let metadata = store.load()
        var groups = [RepositoryGroup]()
        for repository in repositories() {
            let worktrees = await (try? git.worktrees(of: repository)) ?? []
            var items = [WorktreeItem]()
            for worktree in worktrees {
                await items.append(item(worktree: worktree, panes: panes, activity: activity, metadata: metadata))
            }
            groups.append(RepositoryGroup(repository: repository, items: items))
        }
        let foreign = panes
            .filter { SessionName.isAgentIDE($0.sessionName) == false }
            .map { pane in
                AgentSession(
                    name: pane.sessionName,
                    agent: nil,
                    status: pane.isDead ? .finished(pane.exitStatus) : .running,
                    workingDirectory: pane.currentPath,
                )
            }
        return (groups, foreign)
    }

    /// Creates a worktree and branch for a prompt and starts the
    /// agent in tmux, then pastes the prompt into it. `extraArguments`
    /// are appended to the agent command verbatim. Returns the
    /// session name.
    public func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        extraArguments: String = "",
    ) async throws -> String {
        let branch = await availableBranch(repository: repository, prompt: prompt)
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let sessionName = SessionName.make(repository: repository.name, branch: branch, agent: agent)

        let promptFile = try writePrompt(prompt, sessionName: sessionName)
        addFriendlySymlink(repository: repository, branch: branch, worktreePath: worktreePath)

        try await tmux.newSession(
            name: sessionName,
            directory: worktreePath,
            command: runner(for: agent).launchCommand(extraArguments: extraArguments),
        )
        try await tmux.sendPromptFile(promptFile, to: sessionName)

        var metadata = store.load()
        metadata.prompts[sessionName] = prompt
        metadata.arguments[sessionName] = extraArguments
        metadata.lastSeen[sessionName] = Date()
        metadata.sessionsByWorktree[worktreePath] = sessionName
        store.save(metadata)
        return sessionName
    }

    /// Starts an agent in an existing worktree and pastes the prompt,
    /// used by one-click remediation.
    public func launchAgent(
        in worktree: Worktree,
        prompt: String,
        agent: AgentKind,
        extraArguments: String = "",
    ) async throws -> String {
        let sessionName = SessionName.make(repository: worktree.repositoryName, branch: worktree.branch, agent: agent)
        let promptFile = try writePrompt(prompt, sessionName: sessionName)
        try? await tmux.killSession(name: sessionName)
        try await tmux.newSession(
            name: sessionName,
            directory: worktree.path,
            command: runner(for: agent).launchCommand(extraArguments: extraArguments),
        )
        try await tmux.sendPromptFile(promptFile, to: sessionName)
        var metadata = store.load()
        metadata.sessionsByWorktree[worktree.path] = sessionName
        store.save(metadata)
        return sessionName
    }

    /// Pushes the branch and opens a pull request; returns its URL.
    public func pushAndCreatePullRequest(worktree: Worktree) async throws -> String {
        try await git.push(worktreePath: worktree.path, branch: worktree.branch)
        return try await github.createPullRequest(worktreePath: worktree.path)
    }

    /// The argv that attaches a terminal to a session.
    public func attachCommand(sessionName: String) -> [String] {
        tmux.attachCommand(sessionName: sessionName)
    }

    /// The argv for a host-user shell starting in a worktree.
    public func hostShellCommand(worktreePath: String) -> [String] {
        let quoted = "'" + worktreePath.replacing("'", with: "'\\''") + "'"
        return ["/bin/zsh", "-c", "cd " + quoted + " && exec /bin/zsh -il"]
    }

    // MARK: Internal

    let paths: WorkspacePaths
    let git: GitClient
    let tmux: TmuxClient
    let github: GitHubClient
    let transcripts: TranscriptReader
    let spool: EventSpool
    let store: MetadataStore
    let runners: [any AgentRunner]

    func runner(for agent: AgentKind) -> any AgentRunner {
        runners.first { $0.kind == agent } ?? ClaudeCodeRunner()
    }

    func agentKind(of sessionName: String) -> AgentKind? {
        AgentKind.allCases.first { sessionName.hasSuffix("--" + $0.rawValue) }
    }

    func rememberResumeID(sessionName: String, worktreePath: String) {
        guard let agent = agentKind(of: sessionName),
              let directory = runner(for: agent).transcriptDirectory(
                  workingDirectory: worktreePath,
                  sandboxHome: paths.sandboxHome,
              ),
              let transcript = transcripts.latestTranscript(in: directory)
        else {
            return
        }

        var metadata = store.load()
        metadata.resumeIDs[sessionName] = transcripts.resumeID(of: transcript)
        store.save(metadata)
    }

    func writePrompt(_ prompt: String, sessionName: String) throws -> String {
        try FileManager.default.createDirectory(atPath: paths.promptsDirectory, withIntermediateDirectories: true)
        let promptFile = paths.promptsDirectory + "/" + sessionName + ".md"
        try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)
        return promptFile
    }

    func addFriendlySymlink(repository: Repository, branch: String, worktreePath: String) {
        let directory = paths.friendlyWorktreesDirectory + "/" + repository.name
        let link = directory + "/" + branch.replacing("/", with: "-")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: link)
        try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: worktreePath)
    }

    // MARK: Private

    /// How much of the prompt seeds the branch name.
    private static let branchSlugLength = 40

    private func item(
        worktree: Worktree,
        panes: [TmuxPane],
        activity: [String: Date],
        metadata: AppMetadata,
    ) async -> WorktreeItem {
        let pane = panes.first { pane in
            SessionName.isAgentIDE(pane.sessionName) && pane.currentPath == worktree.path
        }
        let session = pane.map { pane in
            AgentSession(
                name: pane.sessionName,
                agent: agentKind(of: pane.sessionName),
                status: pane.isDead ? .finished(pane.exitStatus) : .running,
                workingDirectory: pane.currentPath,
            )
        }
        var unread = false
        if let session, let lastEvent = activity[session.name] {
            unread = lastEvent > (metadata.lastSeen[session.name] ?? .distantPast)
        }
        return await WorktreeItem(
            worktree: worktree,
            session: session,
            isDirty: git.isDirty(worktreePath: worktree.path),
            aheadOfUpstream: git.aheadOfUpstream(worktreePath: worktree.path),
            hasUnread: unread,
        )
    }

    private func availableBranch(repository: Repository, prompt: String) async -> String {
        let base = "agent/" + SessionName.slug(String(prompt.prefix(Self.branchSlugLength)))
        guard await git.branchExists(repository: repository, branch: base) else {
            return base
        }

        var attempt = 2
        while await git.branchExists(repository: repository, branch: "\(base)-\(attempt)") {
            attempt += 1
        }
        return "\(base)-\(attempt)"
    }

    private func createWorktreePath(repository: Repository, branch: String) async throws -> String {
        let existing = await (try? git.worktrees(of: repository)) ?? []
        let prefix = paths.worktreesDirectory + "/"
        let uuid = existing
            .compactMap { worktree -> String? in
                guard worktree.path.hasPrefix(prefix) else {
                    return nil
                }

                return worktree.path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
            }
            .first ?? UUID().uuidString.lowercased()
        let path = prefix + uuid + "/" + branch.replacing("/", with: "-")
        try await git.createWorktree(repository: repository, branch: branch, at: path)
        return path
    }
}
