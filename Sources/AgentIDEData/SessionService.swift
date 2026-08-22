import AgentIDEDomain
import Foundation

// MARK: - SessionServiceError

/// A user-facing service failure with a plain message.
struct SessionServiceError: Error, LocalizedError {
    // MARK: Lifecycle

    /// Creates an error with its displayed message.
    init(_ message: String) {
        self.message = message
    }

    // MARK: Internal

    let message: String

    var errorDescription: String? {
        message
    }
}

// MARK: - SessionService

/// Orchestrates the core loop: worktrees, sessions, review actions
/// and lifecycle. Feature models call this; it composes the clients.
/// Deletion and the repository sessions browser live in their own
/// extension file.
public struct SessionService: Sendable {
    // MARK: Lifecycle

    /// Creates the service.
    public init(
        paths: WorkspacePaths,
        git: GitClient,
        herdr: HerdrClient,
        github: GitHubClient,
        transcripts: TranscriptReader,
        spool: EventSpool,
        store: MetadataStore,
        runners: [any AgentRunner],
        processes: any ProcessRunner = FoundationProcessRunner(),
        launcher: SandvaultLauncher? = nil,
        summariser: FoundationModelClient = FoundationModelClient(),
        progress: @escaping LaunchReporter = silentLaunchReporter,
    ) {
        self.paths = paths
        self.git = git
        self.herdr = herdr
        self.github = github
        self.transcripts = transcripts
        self.spool = spool
        self.store = store
        self.runners = runners
        self.processes = processes
        self.launcher = launcher ?? SandvaultLauncher(hostUser: paths.hostUser)
        self.summariser = summariser
        self.progress = progress
    }

    // MARK: Public

    /// The repositories in the shared workspace.
    public func repositories() -> [Repository] {
        git.repositories(under: paths.repositoriesDirectory)
    }

    /// The full dashboard state: every repository's worktrees joined
    /// with their sessions, plus foreign sessions.
    public func overview() async -> (groups: [RepositoryGroup], foreign: [AgentSession]) {
        let panes = await (try? herdr.panes()) ?? []
        let activity = spool.activity()
        let metadata = store.load()
        var groups = [RepositoryGroup]()
        for repository in repositories() {
            let named = await Repository(
                name: repository.name,
                path: repository.path,
                fullName: git.fullName(of: repository),
            )
            let baseRef = await git.defaultBaseRef(of: repository)
            let worktrees = await (try? git.worktrees(of: repository)) ?? []
            // The main checkout always appears, so repositories show
            // with no worktrees and orphaned conversations stay
            // reachable.
            let mainCheckout = await mainCheckout(of: repository, baseRef: baseRef)
            var items = [WorktreeItem]()
            var seenPaths = Set<String>()
            for worktree in [mainCheckout] + worktrees where seenPaths.insert(worktree.path).inserted {
                await items.append(item(
                    worktree: worktree,
                    baseRef: baseRef,
                    panes: panes,
                    activity: activity,
                    metadata: metadata,
                ))
            }
            // The main checkout stays pinned first; worktrees order by
            // recency of their own work.
            let sorted = [items[0]] + items.dropFirst().sorted { $0.lastActivityAt > $1.lastActivityAt }
            groups.append(RepositoryGroup(
                repository: named,
                items: sorted,
                defaultBranch: baseRef.map(Self.branchName(fromBaseRef:)),
            ))
        }
        // Repositories order by their worktrees' activity; the main
        // checkout's own churn deliberately does not count, except
        // while a session runs there, so resuming on the repository
        // page bumps its repository to the top like a worktree does.
        groups.sort { first, second in
            let firstActivity = Self.repositoryActivity(of: first)
            let secondActivity = Self.repositoryActivity(of: second)
            return firstActivity == secondActivity
                ? first.repository.name < second.repository.name
                : firstActivity > secondActivity
        }
        let foreign = panes
            .filter { SessionName.isAgentIDE($0.sessionName) == false }
            .map(Self.foreignSession(of:))
        // The poll is the only thing running while a session is, so
        // it is what keeps the conversation copies current; the
        // schedule inside means this costs a dictionary lookup on
        // almost every tick.
        await backUpRunningConversations(groups)
        return (groups, foreign)
    }

    /// Creates a worktree and branch for a prompt and starts the
    /// agent in herdr with the picked model, effort and the prompt
    /// as its initial message. Returns the session name.
    public func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        await progress("Naming the branch from the prompt")
        let branch = await availableBranch(repository: repository, prompt: prompt)
        await progress("Creating the worktree for " + branch)
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let slot = WorktreeSlot(repository: repository, branch: branch, path: worktreePath)
        return try await start(prompt: prompt, agent: agent, options: options, slot: slot)
    }

    // MARK: Internal

    /// The most search hits returned to the UI.
    static let searchHitLimit = 200

    /// The most files the fuzzy finder considers.
    static let fileListLimit = 5_000

    /// ripgrep output splits into path, line and text.
    static let searchFieldSplits = 2

    /// Finds Codex conversations by their embedded working
    /// directory; stateless, so no init parameter is needed.
    let codexIndex: CodexTranscriptIndex = .init()

    /// Names branches from prompts on device.
    let summariser: FoundationModelClient

    let paths: WorkspacePaths
    let git: GitClient
    let herdr: HerdrClient
    let github: GitHubClient
    let transcripts: TranscriptReader
    let spool: EventSpool
    let store: MetadataStore
    let runners: [any AgentRunner]
    let processes: any ProcessRunner
    let launcher: SandvaultLauncher

    /// Where launches narrate their steps.
    let progress: LaunchReporter

    /// Worktrees never viewed count as seen at launch, so a fresh
    /// install does not flag every historic conversation unread.
    let startedAt: Date = .init()

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

    /// Launches an agent in a prepared worktree slot: symlink, prompt
    /// file, herdr workspace, paste, metadata.
    func start(
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions,
        slot: WorktreeSlot,
    ) async throws -> String {
        let sessionName = SessionName.make(repository: slot.repository.name, branch: slot.branch, agent: agent)
        let arguments = runner(for: agent).optionArguments(model: options.model, effort: options.effort)
        await progress("Writing the prompt file")
        let promptFile = try writePrompt(prompt, sessionName: sessionName)

        // The prompt travels inside the launch command, read from
        // its file as the agent starts: pasting it after launch
        // raced the agent's terminal setup, which flushed pending
        // input and lost the prompt (Codex reliably, Claude Code
        // sometimes).
        try await startFresh(
            sessionName: sessionName,
            directory: slot.path,
            command: runner(for: agent).launchCommand(extraArguments: arguments, promptFile: promptFile),
        )

        var metadata = store.load()
        metadata.prompts[sessionName] = prompt
        metadata.arguments[sessionName] = arguments
        metadata.seenAt[slot.path] = Date()
        metadata.sessionsByWorktree[slot.path] = sessionName
        metadata.intentionallyClosed.removeAll { $0 == slot.path }
        store.save(metadata)
        return sessionName
    }

    func writePrompt(_ prompt: String, sessionName: String) throws -> String {
        try FileManager.default.createDirectory(atPath: paths.promptsDirectory, withIntermediateDirectories: true)
        let promptFile = paths.promptsDirectory + "/" + sessionName + ".md"
        try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)
        return promptFile
    }

    func createWorktreePath(repository: Repository, branch: String) async throws -> String {
        let path = worktreeContainer(repository: repository) + "/" + branch.replacing("/", with: "-")
        try await git.createWorktree(repository: repository, branch: branch, at: path)
        return path
    }

    /// The repository's worktree directory, a layout the app owns
    /// now the tooling that grouped worktrees by uuid is retired;
    /// worktrees in that older layout keep working because every
    /// listing derives from `git worktree list`.
    func worktreeContainer(repository: Repository) -> String {
        paths.worktreesDirectory + "/" + repository.name
    }

    // MARK: Private

    /// A pane AgentIDE did not create, shown rather than hidden.
    private static func foreignSession(of pane: HerdrPane) -> AgentSession {
        AgentSession(
            name: pane.sessionName,
            agent: nil,
            status: pane.isFinished ? .finished : .running,
            workingDirectory: pane.currentPath,
            paneID: pane.paneID,
            activity: pane.activity,
        )
    }

    /// The repository's own checkout as a worktree: its branch is
    /// whatever is actually checked out, so a feature branch in the
    /// main checkout still matches its pull request in the listing.
    private func mainCheckout(of repository: Repository, baseRef: String?) async -> Worktree {
        await Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: git.currentBranch(worktreePath: repository.path)
                ?? baseRef.map(Self.branchName(fromBaseRef:)) ?? "main",
            path: repository.path,
        )
    }

    private func item(
        worktree: Worktree,
        baseRef: String?,
        panes: [HerdrPane],
        activity: [String: Date],
        metadata: AppMetadata,
    ) async -> WorktreeItem {
        // Matched by the recorded session name first: the pane's
        // current path drifts when the agent changes directory,
        // which made live sessions vanish from the UI.
        let recorded = metadata.sessionsByWorktree[worktree.path]
        let pane = panes.first { pane in
            SessionName.isAgentIDE(pane.sessionName)
                && (pane.sessionName == recorded || pane.currentPath == worktree.path)
        }
        let session = pane.map { pane in
            AgentSession(
                name: pane.sessionName,
                agent: agentKind(of: pane.sessionName),
                status: pane.isFinished ? .finished : .running,
                workingDirectory: pane.currentPath,
                paneID: pane.paneID,
                activity: pane.activity,
                version: metadata.agentVersions[pane.sessionName],
            )
        }
        let past = pastSessions(of: worktree, liveSession: session)

        // Unread is any agent activity since the worktree was last
        // viewed: the event spool and transcript modification count;
        // herdr keeps no output clock, and the spool and transcripts
        // already cover every agent message.
        var lastEvent = Date.distantPast
        if let session, let spooled = activity[session.name] {
            lastEvent = spooled
        }
        if let newest = past.first {
            lastEvent = max(lastEvent, Date(timeIntervalSince1970: TimeInterval(newest.modifiedAt)))
        }
        let seen = metadata.seenAt[worktree.path]
            ?? session.flatMap { metadata.lastSeen[$0.name] }
            ?? startedAt
        let unread = metadata.unreadMarks.contains(worktree.path) || lastEvent > seen

        var counts: (ahead: Int, behind: Int)?
        if let baseRef {
            counts = await git.aheadBehind(worktreePath: worktree.path, baseRef: baseRef)
        }
        let dirty = await git.isDirty(worktreePath: worktree.path)
        var lastActivity = await git.lastCommitDate(worktreePath: worktree.path)
        if let session, session.status == .running || dirty {
            // A live session or uncommitted edits mean work right now.
            lastActivity = Int(Date().timeIntervalSince1970)
        }
        lastActivity = max(lastActivity, Int(lastEvent.timeIntervalSince1970))
        return await WorktreeItem(
            worktree: worktree,
            session: session,
            isDirty: dirty,
            aheadOfUpstream: git.aheadOfUpstream(worktreePath: worktree.path),
            hasUnread: unread,
            pastSessions: past,
            aheadOfDefault: counts?.ahead,
            behindDefault: counts?.behind,
            lastActivityAt: lastActivity,
        )
    }
}
