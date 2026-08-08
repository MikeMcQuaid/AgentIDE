import AgentIDEData
import Foundation
import Testing

/// Exercises the tmux adapter against a real server on a private
/// socket: session lifecycle, pane working directories, dead panes
/// and prompt delivery by paste.
struct TmuxClientIntegrationTests {
    @Test
    func `sessions start in their directory and die visibly`() async throws {
        let tmux = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("pane")
        defer { Task { await tmux.killServer() } }

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
    func `finished panes keep their exit status`() async throws {
        let tmux = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("dead")
        defer { Task { await tmux.killServer() } }

        try await tmux.newSession(name: "agentide--r--dead--claude", directory: directory, command: "exit 7")
        let dead = await TestSupport.poll {
            let panes = await (try? tmux.panes()) ?? []
            return panes.contains { $0.isDead && $0.exitStatus == 7 }
        }
        #expect(dead)
    }

    @Test
    func `prompts arrive as terminal input, not arguments`() async throws {
        let tmux = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("paste")
        defer { Task { await tmux.killServer() } }

        try await tmux.newSession(
            name: "agentide--r--paste--claude",
            directory: directory,
            command: "cat > captured.txt",
        )
        let promptFile = directory + "/prompt.md"
        try "review this branch carefully".write(toFile: promptFile, atomically: true, encoding: .utf8)
        try await tmux.sendPromptFile(promptFile, to: "agentide--r--paste--claude")

        let captured = await TestSupport.poll {
            let content = try? String(contentsOfFile: directory + "/captured.txt", encoding: .utf8)
            return content?.contains("review this branch carefully") ?? false
        }
        #expect(captured)
    }
}
