@testable import AgentIDEData
import Foundation
import Testing

// MARK: - AutofixDeliveryTests

struct AutofixDeliveryTests {
    @Test(arguments: [false, true])
    func `autofix submits its task to the existing visible pane without launching an agent`(
        committing: Bool,
    ) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let runner = ForegroundRunner(known: true)
        let service = world.service(
            herdr: HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true),
        )
        var attempt = AutofixAttempt(
            id: "attempt",
            sources: [.checks],
            head: "head",
            remoteHead: "head",
            localThreadIDs: [],
            branch: "feature",
            worktreePath: world.repository.path,
            sessionName: "agent",
            paneID: "pane",
            threads: [:],
        )
        try await service.deliverAutofix(attempt, text: "Required CI: test failed\nFailure details")
        if committing {
            attempt.commitRequestedHead = "head"
            try await service.deliverAutofix(attempt, text: "")
        }
        let commands = await runner.commands
        let sent = try #require(commands.last { $0.contains("prompt") })
        #expect(sent.last?.hasSuffix("Report progress here.") == true)
        #expect(sent.prefix(4) == ["herdr", "agent", "prompt", "pane"])
        #expect(commands.allSatisfy { arguments in
            arguments.contains("snapshot") || arguments.contains("process-info")
                || arguments.contains("prompt")
        })
        let prompt = try String(contentsOfFile: world.paths.promptsDirectory + "/autofix-attempt.md", encoding: .utf8)
        #expect(prompt.contains("Required CI: test failed\nFailure details"))
        #expect(prompt.contains("Preserve unrelated uncommitted work"))
        #expect(prompt.contains("start another session or push"))
        if committing {
            let file = world.paths.promptsDirectory + "/autofix-attempt-commit.md"
            let followUp = try String(contentsOfFile: file, encoding: .utf8)
            #expect(followUp.contains("commit only the fixes you made"))
            #expect(followUp.contains("autofix-attempt.md"))
            #expect(followUp.contains("start another session or push"))
            #expect(followUp.contains("AgentIDE will verify your committed result and handle pushing"))
        }
    }

    @Test(arguments: [true, false])
    func `delivery requires a known live foreground process`(known: Bool) async throws {
        let runner = ForegroundRunner(known: known)
        let client = HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true)
        if known {
            try await client.sendAutofix("Fix feedback", sessionName: "agent", paneID: "pane")
        } else {
            await #expect(throws: (any Error).self) {
                try await client.sendAutofix("Fix feedback", sessionName: "agent", paneID: "pane")
            }
        }
        #expect(await runner.sent == known)
    }
}

// MARK: - ForegroundRunner

private actor ForegroundRunner: ProcessRunner {
    // MARK: Lifecycle

    init(known: Bool) {
        self.known = known
    }

    // MARK: Internal

    let known: Bool
    var sent = false
    var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        let response: String
        if arguments.contains("snapshot") {
            response = """
            {"result":{"snapshot":{"workspaces":[{"workspace_id":"workspace","label":"agent"}],
            "panes":[{"pane_id":"pane","workspace_id":"workspace","agent":"codex","agent_status":"idle"}]}}}
            """
        } else if arguments.contains("process-info"), known {
            response = """
            {"result":{"process_info":{"shell_pid":1,"foreground_process_group_id":2,
            "foreground_processes":[{"name":"codex"}]}}}
            """
        } else {
            sent = sent || arguments.contains("prompt")
            response = "{}"
        }
        return ProcessResult(status: 0, standardOutput: response, standardError: "")
    }
}
