@testable import AgentIDEData
import Testing

// MARK: - AutofixDeliveryTests

struct AutofixDeliveryTests {
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

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
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
            sent = arguments.contains("send-text")
            response = "{}"
        }
        return ProcessResult(status: 0, standardOutput: response, standardError: "")
    }
}
