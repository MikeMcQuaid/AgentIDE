@testable import AgentIDEData
import Foundation
import Testing

/// Exercises the herdr adapter against a real server on a private
/// config home: workspace lifecycle, working directories, finished
/// detection and typed text.
struct HerdrClientIntegrationTests {
    @Test
    func `sessions start in their directory and die visibly`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("pane")
        defer { TestSupport.stopServerSync(configHome: home) }

        try await herdr.newSession(name: "agentide--r--b--claude", directory: directory, command: "sleep 20")
        let running = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.sessionName == "agentide--r--b--claude" && $0.isFinished == false }
        }
        #expect(running)
        let pane = try #require(try await herdr.panes().first)
        #expect(pane.currentPath == directory)
        #expect(pane.paneID.isEmpty == false)

        try await herdr.killSession(name: "agentide--r--b--claude")
        let gone = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.isEmpty
        }
        #expect(gone)
    }

    @Test
    func `a finished agent leaves its shell back at a prompt`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("dead")
        defer { TestSupport.stopServerSync(configHome: home) }

        try await herdr.newSession(name: "agentide--r--dead--claude", directory: directory, command: "true")
        let finished = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.sessionName == "agentide--r--dead--claude" && $0.isFinished }
        }
        #expect(finished)
    }

    @Test
    func `a repeated label makes a second workspace and one kill closes both`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("fresh")
        defer { TestSupport.stopServerSync(configHome: home) }

        // Labels are not unique to herdr, which is why every fresh
        // start kills the label first; a kill closing every holder
        // is what keeps a raced duplicate from surviving it.
        try await herdr.newSession(name: "agentide--r--fresh--codex", directory: directory, command: "sleep 20")
        try await herdr.newSession(name: "agentide--r--fresh--codex", directory: directory, command: "sleep 20")
        let both = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            let matching = panes.count { $0.sessionName == "agentide--r--fresh--codex" }
            return matching == 2
        }
        #expect(both)

        try await herdr.killSession(name: "agentide--r--fresh--codex")
        let gone = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.isEmpty
        }
        #expect(gone)
    }

    @Test
    func `typed text reaches the pane's terminal`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("type")
        defer { TestSupport.stopServerSync(configHome: home) }

        // `command cat` sidesteps interactive aliases; the terminal
        // is line-buffered, so the newline is what lands the line.
        try await herdr.newSession(
            name: "agentide--r--type--claude",
            directory: directory,
            command: "command cat > typed.txt",
        )
        let running = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.isFinished == false }
        }
        #expect(running)

        try await herdr.typeText("ping\n", sessionName: "agentide--r--type--claude")
        let delivered = await TestSupport.poll {
            let typed = try? String(contentsOfFile: directory + "/typed.txt", encoding: .utf8)
            return typed?.contains("ping") ?? false
        }
        #expect(delivered)
    }
}
