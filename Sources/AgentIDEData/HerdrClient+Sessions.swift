import AgentIDEDomain
import Foundation

// MARK: - SnapshotEnvelope

/// The layers of a `herdr api snapshot` answer this module reads;
/// flat rather than nested because same-file grouping extensions and
/// deeper nesting are both banned.
private struct SnapshotEnvelope: Decodable {
    let result: SnapshotResult?
}

// MARK: - SnapshotResult

private struct SnapshotResult: Decodable {
    let snapshot: Snapshot?
}

// MARK: - Snapshot

private struct Snapshot: Decodable {
    let workspaces: [SnapshotWorkspace]
    let panes: [SnapshotPane]
}

// MARK: - SnapshotWorkspace

private struct SnapshotWorkspace: Decodable {
    // swiftlint:disable explicit_enum_raw_value
    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case label
    }

    // swiftlint:enable explicit_enum_raw_value

    let workspaceID: String
    let label: String
}

// MARK: - SnapshotPane

private struct SnapshotPane: Decodable {
    // swiftlint:disable explicit_enum_raw_value
    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case cwd
        case foregroundCwd = "foreground_cwd"
        case agent
        case agentStatus = "agent_status"
    }

    // swiftlint:enable explicit_enum_raw_value

    let paneID: String
    let workspaceID: String
    let cwd: String?
    let foregroundCwd: String?
    let agent: String?
    let agentStatus: String?
}

// MARK: - CreateEnvelope

/// A `workspace create` answer, read for the root pane to run the
/// agent command in.
private struct CreateEnvelope: Decodable {
    let result: CreateResult?
}

// MARK: - CreateResult

private struct CreateResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case rootPane = "root_pane"
    }

    let rootPane: CreatedPane?
}

// MARK: - CreatedPane

private struct CreatedPane: Decodable {
    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
    }

    let paneID: String
}

// MARK: - ProcessInfoEnvelope

/// A `pane process-info` answer, read to tell an agent still
/// starting (herdr has not recognised it yet) from one that exited
/// back to the pane's shell.
private struct ProcessInfoEnvelope: Decodable {
    let result: ProcessInfoResult?
}

// MARK: - ProcessInfoResult

private struct ProcessInfoResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case processInfo = "process_info"
    }

    let processInfo: PaneProcesses?
}

// MARK: - PaneProcesses

private struct PaneProcesses: Decodable {
    enum CodingKeys: String, CodingKey {
        case shellPID = "shell_pid"
        case foregroundGroupID = "foreground_process_group_id"
        case foregroundProcesses = "foreground_processes"
    }

    let shellPID: Int?
    let foregroundGroupID: Int?
    // Absent, not empty, when herdr cannot resolve the foreground.
    // swiftlint:disable:next discouraged_optional_collection
    let foregroundProcesses: [ForegroundProcess]?
}

// MARK: - ForegroundProcess

private struct ForegroundProcess: Decodable {
    let name: String
}

// MARK: - Foreground

/// What a pane's foreground holds: its own shell at the prompt, or
/// the program it is running.
private struct Foreground {
    let isShell: Bool
    let command: String?
}

// MARK: - SnapshotRow

/// One workspace's identity row out of the snapshot, before the
/// finished enrichment that makes it a `HerdrPane`.
private struct SnapshotRow {
    let sessionName: String
    let workspaceID: String
    let paneID: String
    let currentPath: String
    let agent: String?
    let activity: AgentActivity?
}

// MARK: - StartWait

/// How long a fresh workspace's shell gets to start the command
/// typed into it before creation returns anyway.
private enum StartWait {
    static let polls = 10
    static let pollMilliseconds = 300

    /// How much of the command the narrated step shows.
    static let commandPreview = 120
}

/// herdr's JSON is snake_case; the coding keys above spell it out,
/// since a decoder-wide strategy and the formatter's acronym casing
/// disagree about names like `workspaceID`.
private func decode<Value: Decodable>(_: Value.Type, from text: String) -> Value? {
    try? JSONDecoder().decode(Value.self, from: Data(text.utf8))
}

// MARK: - Sessions

public extension HerdrClient {
    /// Every workspace on the server, empty when no server runs.
    /// Whether an agent is running comes from herdr's detection,
    /// confirmed through the pane's foreground process when herdr
    /// sees none: detection takes a moment after launch, and an
    /// agent that just started must never read as finished.
    func panes() async throws -> [HerdrPane] {
        var panes = [HerdrPane]()
        for row in try await snapshotRows() {
            var foreground = Foreground(isShell: false, command: nil)
            if row.agent == nil {
                foreground = await self.foreground(paneID: row.paneID)
            }
            panes.append(HerdrPane(
                sessionName: row.sessionName,
                paneID: row.paneID,
                isFinished: foreground.isShell,
                activity: row.activity,
                foregroundCommand: foreground.command,
                currentPath: row.currentPath,
            ))
        }
        return panes
    }

    /// Creates a workspace running a command in its root pane's
    /// shell. Callers kill the label first: reusing a workspace
    /// would go on talking to the old process, which after a CLI
    /// upgrade is one whose files have been deleted underneath it.
    /// The pane's `INITIAL_DIR` is pinned because the sandbox's
    /// zshenv changes directory to it, which would otherwise send
    /// agents to the server's directory instead of their worktree.
    /// The command runs under a fresh `TMPDIR`, exported in the
    /// pane's own shell the way sandvault's launcher does for every
    /// session: a server born through sudo resolves no usable
    /// temporary directory of its own, and Codex's execution host
    /// exited during its handshake in panes without one. Per session
    /// rather than per server, so it applies to a server already
    /// running. The first call also births the server inside the
    /// sandbox.
    func newSession(name: String, directory: String, command: String) async throws {
        try await ensureServer()
        await progress("Creating the workspace " + name)
        let created = try await herdr([
            "workspace", "create",
            "--cwd", directory,
            "--label", name,
            "--env", "AGENTIDE_SESSION=" + name,
            "--env", "INITIAL_DIR=" + directory,
            "--no-focus",
        ])
        guard let paneID = decode(CreateEnvelope.self, from: created.standardOutput)?
            .result?
            .rootPane?
            .paneID
        else {
            throw CommandError(command: "herdr workspace create " + name, result: created)
        }

        await progress("Workspace created; its pane is " + paneID)
        await progress("Running: " + command.prefix(StartWait.commandPreview))
        try await herdr(["pane", "run", paneID, "export TMPDIR=\"$(mktemp -d)\"; " + command])
        await progress("Waiting for the shell to hand over to the agent")
        // The command is typed into the pane's just-started shell,
        // which reads it once its own startup finishes; waiting for
        // the shell to hand its foreground over keeps a session
        // observed right after creation from reading as finished. A
        // command that exits instantly hands it straight back, so
        // the wait is bounded rather than required.
        for _ in 0 ..< StartWait.polls {
            guard await foreground(paneID: paneID).isShell else {
                break
            }

            try? await Task.sleep(for: .milliseconds(StartWait.pollMilliseconds))
        }
    }

    /// Closes every workspace holding a label, killing the process
    /// trees inside; absent labels are not an error, so kills stay
    /// idempotent.
    func killSession(name: String) async throws {
        for row in try await snapshotRows() where row.sessionName == name {
            try await herdr(["workspace", "close", row.workspaceID])
        }
    }

    /// Types literal text into a session's terminal.
    func typeText(_ text: String, sessionName: String) async throws {
        guard let row = try await snapshotRows().first(where: { $0.sessionName == sessionName }) else {
            throw CommandError(
                command: "herdr pane send-text",
                result: ProcessResult(status: 1, standardOutput: "", standardError: "No session named " + sessionName),
            )
        }

        try await herdr(["pane", "send-text", row.paneID, text])
    }

    /// The pane's shell process id, the root of everything the
    /// session runs, for resource usage.
    func shellPID(paneID: String) async -> Int? {
        let info = try? await herdr(["pane", "process-info", "--pane", paneID], allowFailure: true)
        return decode(ProcessInfoEnvelope.self, from: info?.standardOutput ?? "")?
            .result?
            .processInfo?
            .shellPID
    }

    // MARK: Private

    /// One row per workspace: its label and its first pane, which is
    /// the root pane AgentIDE created; nothing here splits panes. A
    /// failed listing throws rather than answering empty: an
    /// unanswerable server must never read as a server with nothing
    /// on it, which once let a liveness check declare a just-started
    /// agent dead and the retry kill it.
    private func snapshotRows() async throws -> [SnapshotRow] {
        let result = try await herdr(["api", "snapshot"])
        guard let snapshot = decode(SnapshotEnvelope.self, from: result.standardOutput)?.result?.snapshot else {
            throw CommandError(command: "herdr api snapshot", result: result)
        }

        return snapshot.workspaces.compactMap { workspace in
            guard let pane = snapshot.panes.first(where: { $0.workspaceID == workspace.workspaceID }) else {
                return nil
            }

            return SnapshotRow(
                sessionName: workspace.label,
                workspaceID: workspace.workspaceID,
                paneID: pane.paneID,
                currentPath: pane.foregroundCwd ?? pane.cwd ?? "",
                agent: pane.agent,
                activity: AgentActivity(herdrStatus: pane.agentStatus),
            )
        }
    }

    // MARK: Private

    /// What the pane's foreground holds: the shell itself means
    /// whatever ran in it has exited. An unanswerable pane reads as
    /// still running something, so a hiccup can never kill a live
    /// session.
    private func foreground(paneID: String) async -> Foreground {
        let info = try? await herdr(["pane", "process-info", "--pane", paneID], allowFailure: true)
        guard let processes = decode(ProcessInfoEnvelope.self, from: info?.standardOutput ?? "")?
            .result?
            .processInfo
        else {
            return Foreground(isShell: false, command: nil)
        }
        guard let group = processes.foregroundGroupID else {
            return Foreground(isShell: true, command: nil)
        }

        return Foreground(isShell: group == processes.shellPID, command: processes.foregroundProcesses?.first?.name)
    }
}
