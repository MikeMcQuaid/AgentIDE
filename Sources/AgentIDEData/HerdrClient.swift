import Foundation

// MARK: - HerdrPane

/// One workspace's observed state on the herdr server.
public struct HerdrPane: Sendable {
    /// The workspace label, the session name AgentIDE assigned.
    public let sessionName: String

    /// The root pane's public id, the target terminals attach to.
    public let paneID: String

    /// Whether the launched agent has exited, leaving the pane's
    /// shell back at its prompt: the shell and its scrollback stay
    /// inspectable, herdr's equivalent of a dead pane.
    public let isFinished: Bool

    /// The pane's current working directory.
    public let currentPath: String
}

// MARK: - HerdrClient

/// Talks to the sandbox user's herdr server. Outside the sandbox
/// every call rides the sudoers launch shape; inside it talks to the
/// session's socket directly.
public struct HerdrClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client; `configHome` relocates herdr's sockets and
    /// state entirely (via `XDG_CONFIG_HOME`) so tests isolate whole
    /// throwaway servers. Without it, dev builds and the installed
    /// app use separate named sessions in the server user's own
    /// config home, so neither can list or kill the other's.
    public init(
        runner: any ProcessRunner,
        launcher: SandvaultLauncher,
        isInsideSandbox: Bool,
        configHome: String? = nil,
    ) {
        self.runner = runner
        self.launcher = launcher
        self.isInsideSandbox = isInsideSandbox
        self.configHome = configHome
        sessionName = WorkspacePaths.isProductionBuild ? "agentide" : "agentide-dev"
    }

    // MARK: Public

    /// The argv a terminal pane spawns to control a pane's terminal:
    /// newline-delimited JSON over the pipes, so the pane renders
    /// locally and this client never needs a terminal. `--takeover`
    /// replaces a controller leaked by an earlier app run, which
    /// would otherwise own the pane's input forever; full herdr
    /// clients (SSH attaches) are unaffected.
    public func attachCommand(paneID: String) -> [String] {
        if isInsideSandbox {
            // The channel resolves its argv through `/usr/bin/env`,
            // so leading assignments select the server.
            environment.map { $0.key + "=" + $0.value }.sorted()
                + ["herdr", "terminal", "session", "control", paneID, "--takeover"]
        } else {
            launcher.command(
                payload: exportPrefix + "exec herdr terminal session control "
                    + paneID.shellQuoted + " --takeover",
                initialDirectory: launcher.sharedWorkspace,
                // Deterministic, so the pane's command compares equal
                // across view updates: a fresh UUID here made every
                // update look like a new command and reattach the
                // client in a loop.
                sessionID: paneID,
                sessionName: paneID,
            )
        }
    }

    // MARK: Internal

    /// Ensures the server is up, starting it detached when it is
    /// not: unlike tmux, herdr does not daemonise itself, so birth
    /// is explicit. The whole check-start-wait runs as one payload
    /// because each call from outside the sandbox costs a sudo.
    /// Detaching is zsh's `&!` with redirection alone: this launch
    /// context has no controlling terminal to hang up from, and
    /// macOS's nohup errored over exactly that ("can't detach from
    /// console") without ever starting the server. The server's own
    /// output lands in a log the failure path prints, so a refused
    /// start is never a bare exit code.
    func ensureServer() async throws {
        let log = "\"${XDG_CONFIG_HOME:-$HOME/.config}/herdr/agentide-server.log\""
        let payload = exportPrefix
            + "herdr api snapshot &>/dev/null && exit 0; "
            + (isInsideSandbox ? "" : "cd ~ && ~/configure; "
                + "source ~/.zshenv; source ~/.zprofile; source ~/.zshrc; ")
            + "mkdir -p \"$(dirname " + log + ")\"; "
            + "herdr server &> " + log + " &!; "
            + "for _ in {1..50}; do herdr api snapshot &>/dev/null && exit 0; sleep 0.1; done; "
            + "cat " + log + " >&2; exit 1"
        let argv =
            if isInsideSandbox {
                ["/bin/zsh", "-c", payload]
            } else {
                launcher.command(
                    payload: payload,
                    initialDirectory: launcher.sharedWorkspace,
                    sessionID: UUID().uuidString,
                    sessionName: "agentide-server",
                )
            }
        let result = try await runner.run(argv, workingDirectory: nil, environment: environment)
        guard result.succeeded else {
            throw CommandError(command: "herdr server", result: result)
        }
    }

    /// Runs one herdr CLI command against the selected server.
    @discardableResult
    func herdr(_ arguments: [String], allowFailure: Bool = false) async throws -> ProcessResult {
        let result: ProcessResult
        if isInsideSandbox {
            result = try await runner.run(["herdr"] + arguments, workingDirectory: nil, environment: environment)
        } else {
            let payload = exportPrefix + "exec herdr "
                + arguments.map(\.shellQuoted).joined(separator: " ")
            let argv = launcher.command(
                payload: payload,
                initialDirectory: launcher.sharedWorkspace,
                sessionID: UUID().uuidString,
                sessionName: "agentide-control",
            )
            result = try await runner.run(argv, workingDirectory: nil, environment: [:])
        }
        guard result.succeeded || allowFailure else {
            throw CommandError(command: "herdr " + arguments.joined(separator: " "), result: result)
        }

        return result
    }

    // MARK: Private

    /// The herdr session dev builds and the installed app keep apart.
    private let sessionName: String

    private let runner: any ProcessRunner
    private let launcher: SandvaultLauncher
    private let isInsideSandbox: Bool
    private let configHome: String?

    /// The variables that select the server for a directly spawned
    /// process.
    private var environment: [String: String] {
        configHome.map { ["XDG_CONFIG_HOME": $0] } ?? ["HERDR_SESSION": sessionName]
    }

    /// The same selection for a payload crossing the sudo boundary,
    /// which rebuilds its environment from `env -i`.
    private var exportPrefix: String {
        configHome.map { "export XDG_CONFIG_HOME=" + $0.shellQuoted + "; " }
            ?? "export HERDR_SESSION=" + sessionName.shellQuoted + "; "
    }
}
