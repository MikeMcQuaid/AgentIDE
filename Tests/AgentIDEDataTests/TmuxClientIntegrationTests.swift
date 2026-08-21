@testable import AgentIDEData
import Foundation
import Testing

/// Exercises the tmux adapter against a real server on a private
/// socket: session lifecycle, pane working directories, dead panes
/// and prompt delivery by paste.
struct TmuxClientIntegrationTests {
    @Test
    func `config prelude carries no literal newlines, which sudo login would collapse`() throws {
        let (client, _) = try TestSupport.makeTmuxClient()

        let prelude = client.configPrelude

        #expect(prelude.contains("\n") == false)
        #expect(prelude.contains("\\n"))
        #expect(prelude.contains("mouse on"))
        #expect(prelude.contains("history-limit"))
    }

    @Test
    func `sessions start in their directory and die visibly`() async throws {
        let (tmux, socket) = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("pane")
        defer { TestSupport.killServerSync(socketDirectory: socket) }

        try await tmux.newSession(name: "agentide--r--b--claude", directory: directory, command: "sleep 20")
        let running = await TestSupport.poll {
            let panes = await (try? tmux.panes()) ?? []
            return panes.contains { $0.sessionName == "agentide--r--b--claude" && $0.isDead == false }
        }
        #expect(running)
        let pane = try #require(try await tmux.panes().first)
        #expect(pane.currentPath == directory)

        try await tmux.killSession(name: "agentide--r--b--claude")
        #expect(try await tmux.panes().isEmpty)
    }

    @Test
    func `attach-or-create reuses one shell session, the persistence the host shell relies on`() async throws {
        let socket = try TestSupport.socketDirectory() + "/host"
        let directory = try TestSupport.temporaryDirectory("host-shell")
        let runner = FoundationProcessRunner()
        defer { TestSupport.killServerSync(socketFile: socket) }

        // `-A` attaches instead of creating when the session exists.
        // Detached creation works headlessly; the attach path needs a
        // terminal, which the app's embedded terminal provides, so
        // here it must fail with "not a terminal" rather than create
        // a duplicate.
        let create = ["tmux", "-S", socket, "new-session", "-d", "-A", "-s", "shell", "-c", directory]
        let first = try await runner.run(create, workingDirectory: nil, environment: [:])
        #expect(first.succeeded, "\(first.status): \(first.standardError)")
        let second = try await runner.run(create, workingDirectory: nil, environment: [:])
        #expect(second.standardError.contains("not a terminal"))
        let list = try await runner.run(
            ["tmux", "-S", socket, "list-sessions", "-F", "#{session_name}"],
            workingDirectory: nil,
            environment: [:],
        )
        #expect(list.standardOutput == "shell\n")
    }

    @Test
    func `an agent session refuses to join the one already holding its name`() async throws {
        let (tmux, socket) = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("fresh")
        defer { TestSupport.killServerSync(socketDirectory: socket) }

        try await tmux.newSession(name: "agentide--r--fresh--codex", directory: directory, command: "sleep 20")
        let running = await TestSupport.poll {
            let panes = await (try? tmux.panes()) ?? []
            return panes.contains { $0.sessionName == "agentide--r--fresh--codex" && $0.isDead == false }
        }
        #expect(running)

        // Attach-or-create would hand back the running agent, which
        // after a CLI upgrade is one whose files have gone. Starting
        // fresh means killing the name first, so a clash is a fault.
        await #expect(throws: (any Error).self) {
            try await tmux.newSession(
                name: "agentide--r--fresh--codex",
                directory: directory,
                command: "sleep 20",
            )
        }
    }

    @Test
    func `finished panes keep their exit status`() async throws {
        let (tmux, socket) = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("dead")
        defer { TestSupport.killServerSync(socketDirectory: socket) }

        try await tmux.newSession(name: "agentide--r--dead--claude", directory: directory, command: "exit 7")
        let dead = await TestSupport.poll {
            let panes = await (try? tmux.panes()) ?? []
            return panes.contains { $0.isDead && $0.exitStatus == 7 }
        }
        #expect(dead)
    }
}
