@testable import AgentIDEData
import AgentIDEDomain
import Darwin
import Foundation

// MARK: - TestSupport

/// Shared helpers for integration tests that exercise real git,
/// herdr and filesystem behaviour in isolated temporary locations.
enum TestSupport {
    // MARK: Internal

    /// A fresh temporary directory, fully resolved via `realpath` so
    /// its path matches what git and herdr report for it.
    static func temporaryDirectory(_ label: String) throws -> String {
        try make(label)
    }

    /// A resolved herdr config home, named as briefly as it can be:
    /// a Unix socket path cannot exceed 104 bytes, and this root,
    /// the name and the `herdr/herdr-client.sock` herdr appends stay
    /// inside that.
    static func configHome() throws -> String {
        try make("h")
    }

    /// The fully resolved path, matching git and herdr output.
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

    /// A herdr client on its own private config home, so tests never
    /// touch the real server; the home comes back for
    /// `stopServerSync` in teardown.
    static func makeHerdrClient() throws -> (client: HerdrClient, configHome: String) {
        let home = try configHome()
        let client = HerdrClient(
            runner: FoundationProcessRunner(),
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            configHome: home,
        )
        return (client, home)
    }

    /// Stops a test server and removes its config home,
    /// synchronously: a fire-and-forget Task raced process exit and
    /// leaked servers.
    static func stopServerSync(configHome: String) {
        runSync(["herdr", "server", "stop"], environment: ["XDG_CONFIG_HOME": configHome])
        try? FileManager.default.removeItem(atPath: configHome)
    }

    /// Runs a command to completion, discarding output; teardown
    /// must finish before the process exits, so it cannot await.
    static func runSync(_ argv: [String], environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        var merged = ProcessInfo.processInfo.environment
        // Inherited herdr variables (tests running inside a herdr
        // pane) would aim these teardown stops at the surrounding
        // production server.
        merged["HERDR_SESSION"] = nil
        merged["HERDR_SOCKET_PATH"] = nil
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

    // MARK: Private

    /// Every test's scratch under one swept, gitignored directory in
    /// the checkout, so what a run leaves behind is visible where the
    /// work is rather than loose in a shared temporary directory: a
    /// test that crashes cannot tidy up after itself, and strays were
    /// piling up in `/tmp` a run at a time. A checkout far enough
    /// down the filesystem to overrun a herdr socket's 104-byte path
    /// falls back to this user's own temporary directory.
    private static let root: String = {
        let candidates = [checkoutRoot + "/" + scratchName, NSTemporaryDirectory() + scratchName]
        let path = candidates.first { $0.count + socketBudget <= socketLimit } ?? candidates[1]
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        sweep(path)
        return path
    }()

    /// The checkout this file belongs to: `Tests/<target>/` up.
    private static let checkoutRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path()

    private static let scratchName = ".test-scratch"

    /// What a socket path needs beyond the root: `/h-XXXXXXXX` and
    /// the `/herdr/herdr-client.sock` herdr appends inside it.
    private static let socketBudget = 36

    /// The Unix socket path limit, which a scratch root has to leave
    /// room inside.
    private static let socketLimit = 104

    /// How long a leftover is left alone: long enough that another
    /// test process still using its scratch is never robbed of it,
    /// short enough that nothing survives the next run but the run
    /// before it.
    private static let staleSeconds: TimeInterval = 600

    /// Enough of a UUID to be unique within a run, short enough to
    /// keep socket paths inside their limit.
    private static let idLength = 8

    /// Creates a scratch directory under the swept root, named for
    /// what it holds. The name is short so socket paths stay inside
    /// their length limit.
    private static func make(_ label: String) throws -> String {
        let path = root + "/" + label + "-" + String(UUID().uuidString.prefix(Self.idLength))
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return canonical(path)
    }

    /// Removes what earlier runs left behind.
    private static func sweep(_ path: String) {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-staleSeconds)
        for name in (try? manager.contentsOfDirectory(atPath: path)) ?? [] {
            let entry = path + "/" + name
            let attributes = try? manager.attributesOfItem(atPath: entry)
            guard let modified = attributes?[.modificationDate] as? Date, modified < cutoff else {
                continue
            }

            try? manager.removeItem(atPath: entry)
        }
    }
}

// MARK: - World

/// One temporary world: workspace, repository, herdr and service.
struct World {
    let root: String
    let paths: WorkspacePaths
    let repository: Repository
    let service: SessionService
    let herdr: HerdrClient
    let configHome: String

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
        let home = try TestSupport.configHome()
        let herdrClient = HerdrClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            configHome: home,
        )
        let sessionService = SessionService(
            paths: workspace,
            git: GitClient(runner: runner),
            herdr: herdrClient,
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: workspace.eventsDirectory),
            store: MetadataStore(file: workspace.metadataFile),
            runners: [PromptCaptureRunner()],
            // Disabled so branch names always come from the
            // deterministic prompt fallback, whatever this machine's
            // Apple Intelligence state.
            summariser: FoundationModelClient(isEnabled: false),
        )
        return Self(
            root: base,
            paths: workspace,
            repository: Repository(name: "repo", path: repoPath),
            service: sessionService,
            herdr: herdrClient,
            configHome: home,
        )
    }

    /// Synchronous, so the server dies before the test process can.
    func tearDown() {
        TestSupport.stopServerSync(configHome: configHome)
        try? FileManager.default.removeItem(atPath: root)
    }
}

// MARK: - RecordingRunner

/// Records every command and answers success.
final class RecordingRunner: ProcessRunner, @unchecked Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    private(set) var commands: [[String]] = []

    func run(_ arguments: [String], workingDirectory _: String?, environment _: [String: String]) -> ProcessResult {
        commands.append(arguments)
        return ProcessResult(status: 0, standardOutput: "", standardError: "")
    }
}
