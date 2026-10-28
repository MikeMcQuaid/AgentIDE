import Foundation
import SanductorDomain

// MARK: - RemoteHerdr

/// The Mac's existing herdr and session commands, carried over SSH.
public actor RemoteHerdr {
    // MARK: Lifecycle

    /// Targets the installed Mac app and its named herdr session.
    public init(configuration: SSHConfiguration) {
        self.configuration = configuration
    }

    // MARK: Public

    /// Authenticates without opening a terminal.
    public func connect() async throws {
        try await connection.connect(configuration)
        let help = try await connection.execute(configuration.command(Self.helpCommand(Self.command)))
        try Self.validateCommandHelp(help)
    }

    /// Drops this device’s channels, leaving agents running.
    public func disconnect() async {
        await connection.disconnect()
    }

    /// Reads every workspace and pane from herdr.
    public func snapshot() async throws -> HerdrSnapshot {
        let output = try await connection.execute(configuration.command(["herdr", "api", "snapshot"]))
        return try HerdrSnapshot.decode(Data(output.utf8))
    }

    /// Refreshes changed panes' local Git state without fetching any remote.
    public func worktreeStatuses(in snapshot: HerdrSnapshot, refresh: Bool = false) async throws
        -> [String: GitWorktreeStatus]
    {
        let versions = Self.worktreeVersions(in: snapshot)
        let paths = versions.keys.filter { refresh || worktrees[$0]?.version != versions[$0] }.sorted()
        if paths.isEmpty == false {
            let output = try await connection.execute(configuration.command(Self.worktreeStatusCommand(paths: paths)))
            let updated = Self.parseWorktreeStatuses(output, paths: paths)
            try Task.checkCancellation()
            for path in paths {
                worktrees[path] = RemoteWorktree(version: versions[path] ?? [], status: updated[path])
            }
        }
        worktrees = worktrees.filter { versions[$0.key] != nil }
        return worktrees.compactMapValues(\.status)
    }

    /// Lists checkouts already available to the sandbox user.
    public func repositories() async throws -> [String] {
        try await connection.execute(configuration.command([Self.command, "repositories"]))
            .split(separator: "\n")
            .map(String.init)
    }

    /// Reads the optional sidebar projection last published by this Mac app.
    public func sidebar() async throws -> [SidebarRepository] {
        let script = #"cat "${SHARED_WORKSPACE:-/Users/Shared/sv-${USER#sandvault-}}/sanductor/"#
            + #"sidebar-${HERDR_SESSION}.json""#
            + " 2>/dev/null || true"
        let text = try await connection.execute(configuration.command(["/bin/sh", "-c", script]))
        return (try? JSONDecoder().decode([SidebarRepository].self, from: Data(text.utf8))) ?? []
    }

    /// Reads the choices shared with the desktop’s new-session form.
    public func defaults() async throws -> [String: String] {
        let script = #"cat "${SHARED_WORKSPACE:-/Users/Shared/sv-${USER#sandvault-}}/sanductor/session-defaults""#
            + " 2>/dev/null || true"
        let text = try await connection.execute(configuration.command(["/bin/sh", "-c", script]))
        return text.split(separator: "\n").reduce(into: [:]) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == Self.preferenceFieldCount {
                result[String(parts[0])] = String(parts[1])
            }
        }
    }

    /// Starts one session and returns its pane ID. Never automatically retried.
    public func create(
        repository: String, agent: AgentKind, model: String, effort: String, prompt: String,
    ) async throws -> String {
        let payload = configuration.command([
            Self.command, "new", "--repository", repository, "--agent", agent.rawValue,
            "--model", model, "--effort", effort, "--no-attach",
        ])
        let output = try await connection.execute(payload, input: prompt)
        return try JSONDecoder().decode(CreatedWorkspace.self, from: Data(output.utf8)).result.rootPane.paneID
    }

    /// Claims control of a pane, replacing the other device’s controller.
    public func terminal(paneID: String) async throws -> SSHCommand {
        let payload = configuration.command(["herdr", "terminal", "session", "control", paneID, "--takeover"])
        return try await connection.open(payload)
    }

    /// Subscribes before the initial snapshot so changes cannot be missed.
    public func events(paneIDs: [String]) async throws -> SSHCommand {
        let script = #"exec /usr/bin/nc -U "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/"#
            + #"sessions/${HERDR_SESSION}/herdr.sock""#
        let stream = try await connection.open(configuration.command(["/bin/sh", "-c", script]))
        try stream.send(Self.eventSubscription(paneIDs: paneIDs) + Data("\n".utf8))
        return stream
    }

    // MARK: Internal

    let configuration: SSHConfiguration
    let connection: SSHConnection = .init()

    static func helpCommand(_ command: String) -> [String] {
        ["/bin/sh", "-c", SSHConfiguration.quote(command) + " --help 2>&1 || true"]
    }

    static func validateCommandHelp(_ help: String) throws {
        guard help.contains("sanductor repositories"), help.contains("--no-attach") else {
            throw RemoteError(
                "The Mac app is missing or too old for this iPhone companion. "
                    + "Install the matching Sanductor Mac build in /Applications, then reconnect.",
            )
        }
    }

    static func eventSubscription(paneIDs: [String]) throws -> Data {
        let lifecycle = [
            "workspace.created", "workspace.closed", "workspace.updated", "workspace.renamed",
            "pane.created", "pane.closed", "pane.exited", "pane.agent_detected", "pane.updated",
        ].map { ["type": $0] }
        let status = paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        return try JSONSerialization.data(withJSONObject: [
            "id": "phone", "method": "events.subscribe", "params": ["subscriptions": lifecycle + status],
        ])
    }

    // MARK: Private

    private static let preferenceFieldCount = 2
    private static let command = "/Applications/Sanductor.app/Contents/Resources/bin/sanductor"

    private var worktrees: [String: RemoteWorktree] = [:]
}

// MARK: - CreatedWorkspace

struct CreatedWorkspace: Decodable {
    let result: CreatedResult
}

// MARK: - CreatedResult

struct CreatedResult: Decodable {
    // MARK: Internal

    let rootPane: CreatedPane

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case rootPane = "root_pane"
    }
}

// MARK: - CreatedPane

struct CreatedPane: Decodable {
    // MARK: Internal

    let paneID: String

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
    }
}
