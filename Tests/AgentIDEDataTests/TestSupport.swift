@testable import AgentIDEData
import Darwin
import Foundation

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
    /// the real server.
    static func makeTmuxClient() throws -> TmuxClient {
        try TmuxClient(
            runner: FoundationProcessRunner(),
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            socketDirectory: socketDirectory(),
        )
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
