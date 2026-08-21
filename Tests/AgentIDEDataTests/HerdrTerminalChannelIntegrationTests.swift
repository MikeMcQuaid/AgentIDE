import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the terminal channel against a real herdr server on a
/// private config home: the round trip the terminal panes are built
/// on.
struct HerdrTerminalChannelIntegrationTests {
    @Test
    func `attaching replays the screen and typed keys echo back`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("control")
        defer { TestSupport.stopServerSync(configHome: home) }

        // `command cat` echoes typed lines back through the pane's
        // tty, so one session covers the opening replay, live frames
        // and key delivery.
        try await herdr.newSession(
            name: "agentide--r--control--claude",
            directory: directory,
            command: "command cat",
        )
        let started = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.isFinished == false }
        }
        #expect(started)
        let pane = try #require(try await herdr.panes().first)

        let channel = HerdrTerminalChannel(command: herdr.attachCommand(paneID: pane.paneID))
        let stream = try await channel.start()
        channel.send(HerdrTerminal.resizeCommand(columns: 80, rows: 24))

        // The watchdog releases on timeout, so a silent server ends
        // the stream instead of hanging the test.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            await channel.stop()
        }
        var rendered = [UInt8]()
        var typed = false
        var sawEcho = false
        for await event in stream {
            switch event {
            case let .frame(bytes):
                rendered += bytes
                if typed == false {
                    // The first frame proves the pane is attached;
                    // only then can typing echo back.
                    typed = true
                    channel.send(HerdrTerminal.inputCommand(bytes: Array("ping\r".utf8)))
                }
                if String(bytes: rendered, encoding: .utf8)?.contains("ping") == true {
                    sawEcho = true
                }

            case .closed:
                break
            }
            if sawEcho {
                break
            }
        }
        watchdog.cancel()
        await channel.stop()
        #expect(typed, "the stream should open with a replay frame")
        #expect(sawEcho, "typed keys should echo back as rendered frames")
    }
}
