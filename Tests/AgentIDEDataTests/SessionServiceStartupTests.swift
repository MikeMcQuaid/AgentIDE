@testable import AgentIDEData
import Testing

// MARK: - SessionServiceStartupTests

struct SessionServiceStartupTests {
    @Test(arguments: [false, true])
    func `a missing startup pane waits but a finished pane tries the next command`(finished: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let runner = StartupRunner(finished: finished)
        let service = world.service(herdr: HerdrClient(
            runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true,
        ))

        try await service.start(sessionName: "starting", directory: world.repository.path, trying: ["first", "second"])

        #expect(await runner.creations == (finished ? 2 : 1))
    }
}

// MARK: - StartupRunner

private actor StartupRunner: ProcessRunner {
    // MARK: Lifecycle

    init(finished: Bool) {
        self.finished = finished
    }

    // MARK: Internal

    private(set) var creations = 0

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        var output = ""
        if arguments.contains("create") {
            creations += 1
            active = true
            readings = 0
            output = #"{"result":{"root_pane":{"pane_id":"pane"}}}"#
        } else if arguments.contains("close") {
            active = false
        } else if arguments.contains("snapshot") {
            if active {
                readings += 1
            }
            output = active && readings > 1 ? #"""
            {"result":{"snapshot":{"workspaces":[{"workspace_id":"workspace","label":"starting"}],
            "panes":[{"workspace_id":"workspace","pane_id":"pane","cwd":"/repo"}]}}}
            """# : #"{"result":{"snapshot":{"workspaces":[],"panes":[]}}}"#
        } else if arguments.contains("process-info") {
            // Distinct fixture process IDs.
            // swiftlint:disable:next no_magic_numbers
            let pid = finished && creations == 1 && readings > 1 ? 1 : 2
            output = """
            {"result":{"process_info":{"shell_pid":1,"foreground_process_group_id":\(pid),
            "foreground_processes":[{"name":"sleep"}]}}}
            """
        }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }

    // MARK: Private

    private let finished: Bool
    private var active = false
    private var readings = 0
}
