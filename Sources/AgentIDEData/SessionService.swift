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

    /// A watcher over the workspace roots whose file-system events
    /// decide when a repository's git is worth reading again.
    public func makeWorkspaceWatcher() -> WorkspaceWatcher {
        WorkspaceWatcher(roots: [paths.repositoriesDirectory, paths.worktreesDirectory])
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
        // The version probe costs a sandbox launch of its own, so it
        // runs beside the naming and the worktree rather than in
        // front of the agent. Structured, so a worktree that fails
        // takes the probe with it, and after the quarantine is
        // cleared, since Gatekeeper kills the probe on an install
        // Homebrew left quarantined just as it would the agent.
        await clearQuarantine(for: agent)
        async let probed = probeVersion(of: agent)
        await progress("Naming the branch from the prompt, and asking the CLI its version beside it")
        let branch = await availableBranch(repository: repository, prompt: prompt)
        await progress("Creating the worktree for `" + branch + "`")
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let slot = WorktreeSlot(repository: repository, branch: branch, path: worktreePath)
        return try await start(
            prompt: prompt,
            agent: agent,
            options: options,
            slot: slot,
            probed: probed,
        )
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

    /// See `OverwriteTips`; a default so the public init is
    /// untouched.
    let overwriteTips: OverwriteTips = .init()

    /// See `HostFactsCache`; a default so the public init is
    /// untouched, and a class so every copy of the service shares
    /// what each directory of your own last said.
    let hostFacts: HostFactsCache = .init()

    /// See `PaneLoads`; a default so the public init is untouched,
    /// and a class so every copy of the service shares one set of
    /// pane shells and busy spells.
    let paneLoadCache: PaneLoads = .init()

    /// See `ForkRemotes`; a default so the public init is
    /// untouched, and a class so every copy of the service shares
    /// which fork each checked-out pull request belongs to.
    let forkRemotes: ForkRemotes = .init()

    /// See `LastPanes`; a default so the public init is untouched,
    /// and a class so every copy of the service holds one answer.
    let lastPanes: LastPanes = .init()

    /// See `FileListings`; a default so the public init is
    /// untouched, and a class so every copy of the service shares
    /// one set of in-flight listings.
    let fileListings: FileListings = .init()

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

        store.update { metadata in
            metadata.resumeIDs[sessionName] = transcripts.resumeID(of: transcript)
        }
    }

    /// Launches an agent in a prepared worktree slot: symlink, prompt
    /// file, herdr workspace, paste, metadata.
    func start(
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions,
        slot: WorktreeSlot,
        probed version: String? = nil,
    ) async throws -> String {
        try requireSandboxWorkspace(slot.path)

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
            probed: version,
        )

        await progress("Recording the session `" + sessionName + "`")
        store.update { metadata in
            metadata.prompts[sessionName] = prompt
            metadata.arguments[sessionName] = arguments
            metadata.seenAt[slot.path] = Date()
            metadata.sessionsByWorktree[slot.path] = sessionName
            metadata.intentionallyClosed.removeAll { $0 == slot.path }
        }
        await awaitReady(sessionName: sessionName)
        return sessionName
    }

    func writePrompt(_ prompt: String, sessionName: String) throws -> String {
        try FileManager.default.createDirectory(atPath: paths.promptsDirectory, withIntermediateDirectories: true)
        let promptFile = paths.promptsDirectory + "/" + sessionName + ".md"
        try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)
        return promptFile
    }

    /// The repository's worktree directory, a layout the app owns
    /// now the tooling that grouped worktrees by uuid is retired;
    /// worktrees in that older layout keep working because every
    /// listing derives from `git worktree list`.
    func worktreeContainer(repository: Repository) -> String {
        paths.worktreesDirectory + "/" + repository.name
    }

    // MARK: Private
}
