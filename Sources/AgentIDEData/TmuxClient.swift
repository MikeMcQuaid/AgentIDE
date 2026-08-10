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

    /// The session's last activity as seconds since the epoch, for
    /// unread detection.
    public let activityAt: Int

    /// The pane's current working directory.
    public let currentPath: String
}

// MARK: - TmuxClient

/// Talks to the sandbox user's tmux server. Outside the sandbox every
/// call rides the sudoers launch shape; inside it talks to the shared
/// per-uid socket directly.
public struct TmuxClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client; `socketDirectory` isolates test servers and
    /// defaults to a fixed directory in the sandbox user's home, so
    /// nothing shared lives in world-writable `/tmp`.
    public init(
        runner: any ProcessRunner,
        launcher: SandvaultLauncher,
        isInsideSandbox: Bool,
        socketDirectory: String? = nil,
    ) {
        self.runner = runner
        self.launcher = launcher
        self.isInsideSandbox = isInsideSandbox
        self.socketDirectory = socketDirectory ?? launcher.sandboxHome + "/.agentide/tmux"
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
                activityAt: field.next().flatMap { Int($0) } ?? 0,
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

    // periphery:ignore - reserved for the planned emergency stop.
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
                payload: "export TMUX_TMPDIR=" + shellQuote(socketDirectory)
                    + "; exec tmux attach-session -t " + shellQuote(sessionName),
                initialDirectory: launcher.sharedWorkspace,
                sessionID: UUID().uuidString,
                sessionName: sessionName,
            )
        }
    }

    // MARK: Internal

    /// The shell prelude ensuring the socket directory and config
    /// exist, run as the server's own user: a file written by the
    /// host user would be unreadable across the sudo boundary. The
    /// config's newlines travel as printf escapes, because
    /// `sudo --login` rebuilds the command line and turns literal
    /// newlines into line continuations, which once collapsed the
    /// whole config onto one line.
    var configPrelude: String {
        let format = Self.configContent.replacing("\n", with: "\\n") + "\\n"
        return "export TMUX_TMPDIR=" + shellQuote(socketDirectory) + "; "
            + "mkdir -p " + shellQuote(socketDirectory) + "; "
            + "chmod 700 " + shellQuote(socketDirectory) + "; "
            + "printf " + shellQuote(format) + " > " + shellQuote(configFile) + "; "
    }

    // MARK: Private

    private static let paneFieldCount = 5
    private static let paneFormat =
        "#{session_name}|#{pane_dead}|#{pane_dead_status}|#{session_activity}|#{pane_current_path}"

    /// The server's config: dead panes stay inspectable, the mouse
    /// wheel scrolls tmux's own history (the alternate screen leaves
    /// the outer terminal nothing to scroll) and that history is
    /// deep enough to review a whole session.
    private static let configContent = """
    set -g remain-on-exit on
    set -g mouse on
    set -g history-limit 50000
    set -g default-terminal xterm-256color
    """

    private let runner: any ProcessRunner
    private let launcher: SandvaultLauncher
    private let isInsideSandbox: Bool
    private let socketDirectory: String

    /// tmux only reads `-f` config when it starts the server, so
    /// passing it on every call is harmless and guarantees the
    /// options are set before any pane can exit.
    private var configFile: String {
        socketDirectory + "/agentide.conf"
    }

    @discardableResult
    private func tmux(_ arguments: [String], allowFailure: Bool = false) async throws -> ProcessResult {
        let full = ["-f", configFile] + arguments
        let result: ProcessResult
        if isInsideSandbox {
            try? FileManager.default.createDirectory(atPath: socketDirectory, withIntermediateDirectories: true)
            try? Self.configContent.write(toFile: configFile, atomically: true, encoding: .utf8)
            result = try await runner.run(
                ["tmux"] + full,
                workingDirectory: nil,
                environment: ["TMUX_TMPDIR": socketDirectory],
            )
        } else {
            let payload = configPrelude + "cd ~ && ~/configure; "
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
