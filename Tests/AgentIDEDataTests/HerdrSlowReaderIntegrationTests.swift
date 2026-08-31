import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A whole paste as one command into a reader as slow as an agent
/// redrawing between reads. It holds on an idle machine and fails
/// under load with a kibibyte gone from the middle: the PTY master
/// accepts a write only while the slave's input queue is under
/// `TTYHOG - 2` (1,022 bytes), and herdr 0.8.2 takes a short write
/// as a whole one, so the rest of that piece is dropped whenever
/// the reader stalls long enough for the queue to fill. Kept as the
/// reproduction for the upstream report; enable it again once herdr
/// waits on the terminal or retries.
struct HerdrSlowReaderIntegrationTests {
    @Test(.disabled("herdr 0.8.2 drops the rest of a PTY write the kernel accepted partially"))
    func `a whole paste survives a slow raw-mode reader`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("slow-reader")
        defer { TestSupport.stopServerSync(configHome: home) }

        // Raw mode, 200 bytes every 20 ms: slower than the paste.
        let output = directory + "/received.txt"
        let reader = """
        import os, sys, tty, time
        tty.setraw(0); f = open(sys.argv[1], 'ab'); d = b'x'
        while d and b'\\x04' not in d:
            d = os.read(0, 200); f.write(d); f.flush(); time.sleep(0.02)
        """
        try reader.write(toFile: directory + "/reader.py", atomically: true, encoding: .utf8)
        try await herdr.newSession(
            name: "agentide--r--slow--claude",
            directory: directory,
            command: "python3 reader.py " + output,
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

        let text = (1 ... 1_500)
            .lazy
            .map { String(format: "line %04d ends here and this pads it out", $0) }
            .joined(separator: "\n") + "\n"
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(40))
            await channel.stop()
        }
        for await event in stream {
            if case .frame = event {
                channel.send(HerdrTerminal.inputCommand(bytes: Array(text.utf8) + [0x04]))
                break
            }
        }
        let landed = await TestSupport.poll(timeout: 30) {
            (try? Data(contentsOf: URL(fileURLWithPath: output)))?.last == 0x04
        }
        watchdog.cancel()
        await channel.stop()
        let received = (try? String(contentsOfFile: output, encoding: .utf8)) ?? ""
        let sizes = Comment(rawValue: "sent \(text.utf8.count) bytes, received \(received.utf8.count)")
        #expect(landed && received.dropLast() == text, sizes)
    }
}
