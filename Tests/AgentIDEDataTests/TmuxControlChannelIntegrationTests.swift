import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the control mode channel against a real tmux server on
/// a private socket: the round trip the terminal panes are built on.
struct TmuxControlChannelIntegrationTests {
    @Test
    func `attaching streams history, live output and typed keys`() async throws {
        let (tmux, socket) = try TestSupport.makeTmuxClient()
        let directory = try TestSupport.temporaryDirectory("control")
        defer { TestSupport.killServerSync(socketDirectory: socket) }

        // `cat` echoes typed lines back through the pane's tty, so
        // one session covers history, output and key delivery.
        try await tmux.newSession(
            name: "agentide--r--control--claude",
            directory: directory,
            command: "printf 'ready\\n'; exec cat",
        )
        let started = await TestSupport.poll {
            let panes = await (try? tmux.panes()) ?? []
            return panes.contains { $0.isDead == false }
        }
        #expect(started)

        let channel = TmuxControlChannel(
            command: tmux.attachCommand(sessionName: "agentide--r--control--claude"),
            environment: ["TMUX_TMPDIR": socket],
        )
        let stream = try await channel.start()
        channel.send(TmuxControl.resizeCommand(columns: 80, rows: 24))
        channel.send(TmuxControl.historyCommand)

        // The watchdog detaches on timeout, so a silent server ends
        // the stream instead of hanging the test.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            await channel.stop()
        }
        var sawHistory = false
        var sawEcho = false
        for await event in stream {
            switch event {
            case let .response(lines, isError):
                if isError == false, lines.contains(where: { $0.contains("ready") }), sawHistory == false {
                    sawHistory = true
                    channel.send(TmuxControl.sendKeysCommand(bytes: Array("ping\r".utf8)))
                }

            case let .output(_, bytes):
                if String(bytes: bytes, encoding: .utf8)?.contains("ping") == true {
                    sawEcho = true
                }

            case .exited,
                 .notification:
                break
            }
            if sawHistory, sawEcho {
                break
            }
        }
        watchdog.cancel()
        await channel.stop()
        #expect(sawHistory, "capture-pane should report the pane's history")
        #expect(sawEcho, "typed keys should echo back as pane output")
    }
}
