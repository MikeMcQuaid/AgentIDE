import Foundation

// MARK: - TmuxPane

/// One tmux pane's observed state.
public struct TmuxPane: Sendable {
    /// The pane's session name.
    public let sessionName: String

    /// Whether the pane's process has exited.
    public let isDead: Bool

    /// The dead pane's exit status, when available.
    public let exitStatus: Int?

    /// The pane's current working directory.
    public let currentPath: String
}

// MARK: - TmuxClient

/// Talks to the sandbox user's tmux server. Outside the sandbox every
/// call rides the sudoers launch shape; inside it talks to the shared
/// per-uid socket directly.
public struct TmuxClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client; `socketDirectory` isolates test servers.
    public init(
        runner: any ProcessRunner,
        launcher: SandvaultLauncher,
        isInsideSandbox: Bool,
        socketDirectory: String = "/tmp",
    ) {
        self.runner = runner
        self.launcher = launcher
        self.isInsideSandbox = isInsideSandbox
        self.socketDirectory = socketDirectory
    }

    // MARK: Public

    /// Every pane on the server, empty when no server runs. Fields are
    /// joined by `|`: tmux replaces control characters like tab in
    /// `-F` output, so a printable separator is required. Only the
    /// trailing path can contain `|`, so its pieces are rejoined.
    public func panes() async throws -> [TmuxPane] {
        let result = try await tmux(["list-panes", "-a", "-F", Self.paneFormat], allowFailure: true)
        guard result.succeeded else {
            return []
        }

        return result.standardOutput.split(separator: "\n").compactMap { line in
            // maxSplits keeps a `|` inside the trailing path intact.
            let fields = line.split(
                separator: "|",
                maxSplits: Self.paneFieldCount - 1,
                omittingEmptySubsequences: false,
            )
            guard fields.count == Self.paneFieldCount else {
                return nil
            }

            var field = fields.map(String.init).makeIterator()
            return TmuxPane(
                sessionName: field.next() ?? "",
                isDead: field.next() == "1",
                exitStatus: field.next().flatMap { Int($0) },
                currentPath: field.next() ?? "",
            )
        }
    }

    /// Creates a detached session running a command. `remain-on-exit`
    /// comes from the server config so even an agent that exits
    /// immediately leaves an inspectable dead pane. The pane's
    /// `INITIAL_DIR` is pinned because the sandbox's zshenv changes
    /// directory to it, which would otherwise send agents to the
    /// server's directory instead of their worktree. The first call
    /// also births the server inside the sandbox.
    public func newSession(name: String, directory: String, command: String) async throws {
        try await tmux([
            "new-session", "-A", "-d",
            "-s", name,
            "-c", directory,
            "-e", "AGENTIDE_SESSION=" + name,
            "-e", "INITIAL_DIR=" + directory,
            command,
        ])
    }

    /// Pastes a file's content into a session's terminal and presses
    /// return, so prompts reach agents as input rather than argv.
    public func sendPromptFile(_ file: String, to sessionName: String) async throws {
        try await tmux([
            "load-buffer", file,
            ";", "paste-buffer", "-d", "-p", "-t", sessionName,
            ";", "send-keys", "-t", sessionName, "Enter",
        ])
    }

    /// Kills one session, leaving the server and its siblings alone.
    public func killSession(name: String) async throws {
        try await tmux(["kill-session", "-t", name])
    }

    // periphery:ignore - used by integration tests, which the app
    // scheme periphery scans excludes, and by the planned emergency stop.
    /// Kills the whole server.
    public func killServer() async {
        _ = try? await tmux(["kill-server"], allowFailure: true)
    }

    /// The argv a terminal view should spawn to attach interactively.
    public func attachCommand(sessionName: String) -> [String] {
        if isInsideSandbox {
            ["tmux", "attach-session", "-t", sessionName]
        } else {
            launcher.command(
                payload: "export TMUX_TMPDIR=" + socketDirectory
                    + "; exec tmux attach-session -t " + shellQuote(sessionName),
                initialDirectory: launcher.sharedWorkspace,
                sessionID: UUID().uuidString,
                sessionName: sessionName,
            )
        }
    }

    // MARK: Private

    private static let paneFieldCount = 4
    private static let paneFormat =
        "#{session_name}|#{pane_dead}|#{pane_dead_status}|#{pane_current_path}"

    private let runner: any ProcessRunner
    private let launcher: SandvaultLauncher
    private let isInsideSandbox: Bool
    private let socketDirectory: String

    /// tmux only reads `-f` config when it starts the server, so
    /// passing it on every call is harmless and guarantees
    /// `remain-on-exit` is set before any pane can exit. tmux config
    /// can run shell commands, so the file is always overwritten with
    /// the minimal content and owner-only permissions rather than
    /// trusting whatever might already sit in the shared socket
    /// directory.
    private func configArguments() -> [String] {
        let configFile = socketDirectory + "/agentide.conf"
        try? FileManager.default.createDirectory(atPath: socketDirectory, withIntermediateDirectories: true)
        try? "set -g remain-on-exit on\n".write(toFile: configFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile)
        return ["-f", configFile]
    }

    @discardableResult
    private func tmux(_ arguments: [String], allowFailure: Bool = false) async throws -> ProcessResult {
        let full = configArguments() + arguments
        let result: ProcessResult
        if isInsideSandbox {
            result = try await runner.run(
                ["tmux"] + full,
                workingDirectory: nil,
                environment: ["TMUX_TMPDIR": socketDirectory],
            )
        } else {
            let payload = "export TMUX_TMPDIR=" + socketDirectory + "; cd ~ && ~/configure; "
                + "source ~/.zshenv; source ~/.zprofile; source ~/.zshrc; "
                + "exec tmux " + full.map(shellQuote).joined(separator: " ")
            let argv = launcher.command(
                payload: payload,
                initialDirectory: launcher.sharedWorkspace,
                sessionID: UUID().uuidString,
                sessionName: "agentide-control",
            )
            result = try await runner.run(argv, workingDirectory: nil, environment: [:])
        }
        guard result.succeeded || allowFailure else {
            throw CommandError(command: "tmux " + arguments.joined(separator: " "), result: result)
        }

        return result
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }
}
