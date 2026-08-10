@testable import AgentIDEData
import AgentIDEDomain
import Darwin
import Foundation

// MARK: - TestSupport

/// Shared helpers for integration tests that exercise real git, tmux
/// and filesystem behaviour in isolated temporary locations.
enum TestSupport {
    /// A fresh temporary directory, fully resolved via `realpath` so
    /// its path matches what git and tmux report for it.
    static func temporaryDirectory(_ label: String) throws -> String {
        let path = "/tmp/agentide-" + label + "-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return canonical(path)
    }

    /// A short-lived, resolved tmux socket directory under `/tmp`; the
    /// deep temp hierarchy overruns the 104-byte Unix socket path
    /// limit.
    static func socketDirectory() throws -> String {
        let path = "/tmp/av-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return canonical(path)
    }

    /// The fully resolved path, matching git and tmux output.
    static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return path
        }

        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Runs a command, throwing on failure.
    @discardableResult
    static func run(_ arguments: [String], in directory: String? = nil) async throws -> ProcessResult {
        let result = try await FoundationProcessRunner()
            .run(arguments, workingDirectory: directory, environment: [:])
        guard result.succeeded else {
            throw CommandError(command: arguments.joined(separator: " "), result: result)
        }

        return result
    }

    /// Runs git with hooks and signing neutralised, so user-level
    /// configuration cannot leak into tests.
    @discardableResult
    static func runGit(_ arguments: [String], in directory: String) async throws -> ProcessResult {
        try await run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"] + arguments,
            in: directory,
        )
    }

    /// Initialises a git repository with an identity and one commit.
    static func makeRepository(at path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "main"], in: path)
        try await runGit(["config", "user.email", "test@example.com"], in: path)
        try await runGit(["config", "user.name", "Test"], in: path)
        try await runGit(["config", "commit.gpgsign", "false"], in: path)
        try await runGit(["config", "core.hooksPath", "/dev/null"], in: path)
        try "hello\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Initial commit"], in: path)
    }

    /// A tmux client on its own private socket, so tests never touch
    /// the real server; the socket directory comes back for
    /// `killServerSync` in teardown.
    static func makeTmuxClient() throws -> (client: TmuxClient, socketDirectory: String) {
        let socket = try socketDirectory()
        let client = TmuxClient(
            runner: FoundationProcessRunner(),
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            socketDirectory: socket,
        )
        return (client, socket)
    }

    /// Kills a test server and removes its socket directory,
    /// synchronously: a fire-and-forget Task raced process exit and
    /// leaked servers.
    static func killServerSync(socketDirectory: String) {
        runSync(["tmux", "kill-server"], environment: ["TMUX_TMPDIR": socketDirectory])
        try? FileManager.default.removeItem(atPath: socketDirectory)
    }

    /// Kills a test server addressed by socket file, synchronously.
    static func killServerSync(socketFile: String) {
        runSync(["tmux", "-S", socketFile, "kill-server"], environment: [:])
    }

    /// Runs a command to completion, discarding output; teardown
    /// must finish before the process exits, so it cannot await.
    static func runSync(_ argv: [String], environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            merged[key] = value
        }
        process.environment = merged
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Polls a condition until it holds or the timeout passes.
    static func poll(timeout: Double = 5, until condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }
}

// MARK: - World

/// One temporary world: workspace, repository, tmux and service.
struct World {
    let root: String
    let paths: WorkspacePaths
    let repository: Repository
    let service: SessionService
    let tmux: TmuxClient
    let socketDirectory: String

    static func make() async throws -> Self {
        let base = try TestSupport.temporaryDirectory("world")
        let workspace = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: base + "/shared",
            sandboxHome: base + "/home",
            metadataFile: base + "/state.json",
        )
        let repoPath = workspace.repositoriesDirectory + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let runner = FoundationProcessRunner()
        let socket = try TestSupport.socketDirectory()
        let tmuxClient = TmuxClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            socketDirectory: socket,
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
            socketDirectory: socket,
        )
    }

    /// Synchronous, so the server dies before the test process can.
    func tearDown() {
        TestSupport.killServerSync(socketDirectory: socketDirectory)
        try? FileManager.default.removeItem(atPath: root)
    }
}
