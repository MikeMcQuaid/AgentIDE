@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the terminal channel against a real herdr server on a
/// private config home: the round trip the terminal panes are built
/// on.
struct HerdrTerminalChannelIntegrationTests {
    @Test
    func `scrolling a mouse-aware agent carries the pointer position`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("scroll")
        defer { TestSupport.stopServerSync(configHome: home) }
        let input = directory + "/mouse-input"
        try await herdr.newSession(
            name: "agentide--r--scroll--codex",
            directory: directory,
            command: "stty raw -echo; printf '\\033[?1049h\\033[?1000h\\033[?1006hscroll-%s' ready; "
                + "dd bs=1 count=10 of=" + input.shellQuoted + " 2>/dev/null; stty sane",
        )
        let pane = try #require(try await herdr.panes().first)
        let channel = HerdrTerminalChannel(command: herdr.attachCommand(paneID: pane.paneID))
        let stream = try await channel.start()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            await channel.stop()
        }
        for await event in stream {
            if case let .frame(bytes) = event,
               String(bytes: bytes, encoding: .utf8)?.contains("scroll-ready") == true
            {
                channel.send(HerdrTerminal.scrollCommand(upwards: true, lines: 1, column: 7, row: 4))
                break
            }
        }
        let received = await TestSupport.poll(timeout: 5) {
            (try? Data(contentsOf: URL(filePath: input)).count) == 10
        }
        watchdog.cancel()
        await channel.stop()
        try #require(received)
        #expect(try Data(contentsOf: URL(filePath: input)) == Data("\u{1B}[<64;8;5M".utf8))
    }

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
            try? await Task.sleep(for: .seconds(30))
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
