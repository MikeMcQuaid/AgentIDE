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
        // Dev builds and tests get their own server socket, so they
        // can never touch the installed app's sessions.
        self.socketDirectory = socketDirectory ?? launcher.sandboxHome
            + (WorkspacePaths.isProductionBuild ? "/.agentide/tmux" : "/.agentide/tmux-dev")
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

    /// Kills one session, leaving the server and its siblings alone.
    public func killSession(name: String) async throws {
        try await tmux(["kill-session", "-t", name])
    }

    /// Types literal text into a session, as pasted input.
    public func typeText(_ text: String, sessionName: String) async throws {
        try await tmux(["send-keys", "-l", "-t", sessionName, text])
    }

    /// The argv a terminal pane spawns to attach as a control mode
    /// client: `-C` speaks the textual protocol over the pipes, so
    /// the pane renders locally and this client never needs a
    /// terminal. External SSH attaches still get mouse and OSC 52
    /// copying from the server config.
    public func attachCommand(sessionName: String) -> [String] {
        if isInsideSandbox {
            ["tmux", "-C", "attach-session", "-t", sessionName]
        } else {
            launcher.command(
                payload: "export TMUX_TMPDIR=" + socketDirectory.shellQuoted
                    + "; exec tmux -C attach-session -t " + sessionName.shellQuoted,
                initialDirectory: launcher.sharedWorkspace,
                // Deterministic, so the pane's command compares equal
                // across view updates: a fresh UUID here made every
                // update look like a new command and reattach the
                // client in a loop.
                sessionID: sessionName,
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
        return "export TMUX_TMPDIR=" + socketDirectory.shellQuoted + "; "
            + "mkdir -p " + socketDirectory.shellQuoted + "; "
            + "chmod 700 " + socketDirectory.shellQuoted + "; "
            + "printf " + format.shellQuoted + " > " + configFile.shellQuoted + "; "
    }

    // MARK: Private

    private static let paneFieldCount = 5
    private static let paneFormat =
        "#{session_name}|#{pane_dead}|#{pane_dead_status}|#{session_activity}|#{pane_current_path}"

    /// The server's config: dead panes stay inspectable, the mouse
    /// wheel scrolls tmux's own history (the alternate screen leaves
    /// the outer terminal nothing to scroll) and that history is
    /// deep enough to review a whole session. `set-clipboard` with
    /// the clipboard terminal feature makes copy-mode yanks reach
    /// the macOS clipboard through OSC 52.
    private static let configContent = """
    set -g remain-on-exit on
    set -g mouse on
    set -g history-limit 50000
    set -g default-terminal xterm-256color
    set -g status off
    set -s set-clipboard on
    set -as terminal-features xterm-256color:clipboard
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
                + "exec tmux " + full.map(\.shellQuoted).joined(separator: " ")
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
}
