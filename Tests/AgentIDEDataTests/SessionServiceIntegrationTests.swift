import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - PromptCaptureRunner

/// A fake agent that records its arguments and captures the pasted
/// prompt, standing in for a real CLI in integration tests.
struct PromptCaptureRunner: AgentRunner {
    var kind: AgentKind {
        .claudeCode
    }

    func launchCommand(extraArguments: String) -> String {
        let quoted = "'" + extraArguments.replacing("'", with: "'\\''") + "'"
        return "printf '%s' " + quoted + " > agent-arguments.txt; cat > agent-prompt.txt"
    }

    func resumeCommand(resumeID: String, extraArguments _: String) -> String {
        "printf '%s' '" + resumeID + "' > agent-resumed.txt; cat > /dev/null"
    }

    func transcriptDirectory(workingDirectory _: String, sandboxHome: String) -> String? {
        sandboxHome + "/transcripts"
    }
}

// MARK: - SessionServiceIntegrationTests

/// Drives the whole core loop against real git, a private tmux
/// server and a temporary workspace: create, observe, archive and
/// undelete.
struct SessionServiceIntegrationTests {
    // MARK: Internal

    @Test
    func `create session builds worktree, symlink, prompt and running pane`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        let name = try await world.service.createSession(
            repository: world.repository,
            prompt: "Do the thing",
            agent: .claudeCode,
            extraArguments: "--model fable --effort max",
        )
        #expect(SessionName.isAgentIDE(name))

        let overview = await world.service.overview()
        let item = try #require(overview.groups.first?.items.first)
        #expect(item.session?.name == name)
        #expect(item.session?.status == SessionStatus.running)
        let worktreePath = item.worktree.path

        let delivered = await TestSupport.poll {
            let prompt = try? String(contentsOfFile: worktreePath + "/agent-prompt.txt", encoding: .utf8)
            return prompt?.contains("Do the thing") ?? false
        }
        #expect(delivered)
        let arguments = try String(contentsOfFile: worktreePath + "/agent-arguments.txt", encoding: .utf8)
        #expect(arguments == "--model fable --effort max")

        let symlink = world.paths.friendlyWorktreesDirectory + "/repo/agent-do-the-thing"
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlink)
        #expect(destination == worktreePath)
    }

    @Test
    func `archive removes the worktree and undelete restores it in place`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        _ = try await world.service.createSession(
            repository: world.repository,
            prompt: "Recoverable work",
            agent: .claudeCode,
        )
        let overview = await world.service.overview()
        let item = try #require(overview.groups.first?.items.first)
        let worktreePath = item.worktree.path
        try "loose\n".write(toFile: worktreePath + "/untracked.txt", atomically: true, encoding: .utf8)

        let archive = try await world.service.archiveAndDelete(item: item)
        #expect(FileManager.default.fileExists(atPath: worktreePath) == false)
        let archiveDirectory = world.paths.archivesDirectory + "/" + archive.id
        #expect(FileManager.default.fileExists(atPath: archiveDirectory + "/branch.bundle"))
        #expect(FileManager.default.fileExists(atPath: archiveDirectory + "/metadata.json"))

        try await world.service.undelete(archive: archive)
        #expect(FileManager.default.fileExists(atPath: worktreePath + "/README.md"))
        #expect(FileManager.default.fileExists(atPath: worktreePath + "/untracked.txt"))
        let after = await world.service.overview()
        #expect(after.groups.first?.items.first?.worktree.path == worktreePath)
    }

    // MARK: Private

    /// One temporary world: workspace, repository, tmux and service.
    private struct World {
        let root: String
        let paths: WorkspacePaths
        let repository: Repository
        let service: SessionService
        let tmux: TmuxClient

        static func make() async throws -> Self {
            let base = try TestSupport.temporaryDirectory("world")
            let workspace = WorkspacePaths(
                hostUser: "test",
                sharedWorkspace: base + "/shared",
                sandboxHome: base + "/home",
                archivesDirectory: base + "/archives",
                metadataFile: base + "/state.json",
            )
            let repoPath = workspace.repositoriesDirectory + "/repo"
            try await TestSupport.makeRepository(at: repoPath)
            let runner = FoundationProcessRunner()
            let tmuxClient = try TmuxClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                socketDirectory: TestSupport.socketDirectory(),
            )
            let sessionService = SessionService(
                paths: workspace,
                git: GitClient(runner: runner),
                tmux: tmuxClient,
                github: GitHubClient(runner: runner),
                transcripts: TranscriptReader(),
                spool: EventSpool(directory: workspace.eventsDirectory),
                store: MetadataStore(file: workspace.metadataFile),
                runners: [PromptCaptureRunner()],
            )
            return Self(
                root: base,
                paths: workspace,
                repository: Repository(name: "repo", path: repoPath),
                service: sessionService,
                tmux: tmuxClient,
            )
        }

        func tearDown() {
            let server = tmux
            let directory = root
            Task {
                await server.killServer()
                try? FileManager.default.removeItem(atPath: directory)
            }
        }
    }
}
