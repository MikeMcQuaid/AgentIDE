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
    }

    let shellPID: Int?
    let foregroundGroupID: Int?
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
            var isFinished = false
            if row.agent == nil {
                isFinished = await shellIsForeground(paneID: row.paneID)
            }
            panes.append(HerdrPane(
                sessionName: row.sessionName,
                paneID: row.paneID,
                isFinished: isFinished,
                activity: row.activity,
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
    /// The first call also births the server inside the sandbox.
    func newSession(name: String, directory: String, command: String) async throws {
        try await ensureServer()
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

        try await herdr(["pane", "run", paneID, command])
        // The command is typed into the pane's just-started shell,
        // which reads it once its own startup finishes; waiting for
        // the shell to hand its foreground over keeps a session
        // observed right after creation from reading as finished. A
        // command that exits instantly hands it straight back, so
        // the wait is bounded rather than required.
        for _ in 0 ..< StartWait.polls {
            guard await shellIsForeground(paneID: paneID) else {
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
    /// the root pane AgentIDE created; nothing here splits panes.
    private func snapshotRows() async throws -> [SnapshotRow] {
        let result = try await herdr(["api", "snapshot"], allowFailure: true)
        guard result.succeeded,
              let snapshot = decode(SnapshotEnvelope.self, from: result.standardOutput)?.result?.snapshot
        else {
            return []
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

    /// Whether the pane's shell owns its own foreground, meaning
    /// whatever ran in it has exited. An unanswerable pane reads as
    /// still running, so a hiccup can never kill a live session.
    private func shellIsForeground(paneID: String) async -> Bool {
        let info = try? await herdr(["pane", "process-info", "--pane", paneID], allowFailure: true)
        guard let processes = decode(ProcessInfoEnvelope.self, from: info?.standardOutput ?? "")?
            .result?
            .processInfo
        else {
            return false
        }
        guard let foreground = processes.foregroundGroupID else {
            return true
        }

        return foreground == processes.shellPID
    }
}
