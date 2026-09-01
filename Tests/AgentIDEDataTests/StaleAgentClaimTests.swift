@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - StaleAgentClaimTests

/// A reboot leaves herdr's own records claiming agents whose
/// processes died with the machine: the workspace comes back, its
/// pane sits at a login shell, and herdr still names an agent. A
/// resume that believed the claim did nothing and attached to that
/// shell, which is what a reboot looked like from the middle pane.
struct StaleAgentClaimTests {
    // MARK: Internal

    @Test
    func `a claimed agent whose pane is at a shell is not a live session`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let worktree = world.repository.path
        let service = Self.service(world: world, foregroundIsShell: true)

        // herdr says an agent is there; the pane says otherwise, and
        // the pane is the process that would have to be running.
        #expect(await service.hasLiveSession(worktreePath: worktree) == false)

        // The row and its pane read the same listing, so neither
        // shows a session the reboot took away.
        let panes = try await Self.herdr(world: world, foregroundIsShell: true).panes()
        #expect(panes.first?.isFinished == true)
    }

    @Test
    func `an agent really in the foreground still counts as live`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let worktree = world.repository.path
        let service = Self.service(world: world, foregroundIsShell: false)

        #expect(await service.hasLiveSession(worktreePath: worktree))
    }

    // MARK: Private

    /// A service whose herdr answers from the script rather than a
    /// server, so the pane's state is the test's to choose.
    private static func herdr(world: World, foregroundIsShell: Bool) -> HerdrClient {
        HerdrClient(
            runner: StaleClaimRunner(
                sessionName: "agentide--repo--work--claude",
                worktree: world.repository.path,
                foregroundIsShell: foregroundIsShell,
            ),
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            configHome: world.configHome,
        )
    }

    private static func service(world: World, foregroundIsShell: Bool) -> SessionService {
        let real = FoundationProcessRunner()
        return SessionService(
            paths: world.paths,
            git: GitClient(runner: real),
            herdr: herdr(world: world, foregroundIsShell: foregroundIsShell),
            github: GitHubClient(runner: real),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: world.paths.eventsDirectory),
            store: MetadataStore(file: world.paths.metadataFile),
            runners: [],
        )
    }
}

// MARK: - StaleClaimRunner

/// Answers a snapshot naming an agent, and a process listing whose
/// foreground is the pane's own shell unless told otherwise.
private struct StaleClaimRunner: ProcessRunner {
    /// Arbitrary identifiers: what matters is whether the pane's
    /// foreground group is its own shell.
    static let shellPID = 100
    static let agentPID = 200

    let sessionName: String
    let worktree: String
    var foregroundIsShell = true

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) -> ProcessResult {
        let output =
            if arguments.contains("snapshot") {
                """
                {"result": {"snapshot": {
                  "workspaces": [{"workspace_id": "w1", "label": "\(sessionName)"}],
                  "panes": [{"pane_id": "w1:p1", "workspace_id": "w1", "cwd": "\(worktree)",
                             "agent": "claude", "agent_status": "idle"}]
                }}}
                """
            } else if arguments.contains("process-info") {
                """
                {"result": {"process_info": {
                  "shell_pid": \(Self.shellPID),
                  "foreground_process_group_id": \(foregroundIsShell ? Self.shellPID : Self.agentPID),
                  "foreground_processes": [{"name": "\(foregroundIsShell ? "zsh" : "claude")"}]
                }}}
                """
            } else {
                ""
            }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}
