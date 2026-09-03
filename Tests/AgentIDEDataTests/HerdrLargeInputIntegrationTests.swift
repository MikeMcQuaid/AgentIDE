import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A whole paste as one input command: herdr must deliver every
/// byte to the pane's terminal, in order.
///
/// The same herdr 0.8.2 bug `HerdrSlowReaderIntegrationTests`
/// isolates: a short PTY write taken as a whole one loses about a
/// kibibyte whenever the reader stalls with the queue full. It used
/// to fail now and then; with the sandbox's run capped and put in
/// the background band it stalls on every run, and a suite that
/// always fails hides the failures worth reading. Enable it again
/// once herdr waits on the terminal or retries.
struct HerdrLargeInputIntegrationTests {
    @Test(.disabled("herdr 0.8.2 drops the rest of a PTY write the kernel accepted partially"))
    func `a large input reaches the pane whole`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("large-input")
        defer { TestSupport.stopServerSync(configHome: home) }

        let output = directory + "/received.txt"
        try await herdr.newSession(
            name: "agentide--r--large--claude",
            directory: directory,
            command: "command cat > " + output,
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

        // Numbered lines, so whatever survives says which part did.
        let text = (1 ... 4_000)
            .lazy
            .map { String(format: "line %04d ends here and this pads it out", $0) }
            .joined(separator: "\n") + "\n"
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(15))
            await channel.stop()
        }
        for await event in stream {
            if case .frame = event {
                channel.send(HerdrTerminal.inputCommand(bytes: Array(text.utf8)))
                // End of input at a line start ends cat and flushes.
                channel.send(HerdrTerminal.inputCommand(bytes: [0x04]))
                break
            }
        }
        let last = "line 4000 ends here and this pads it out\n"
        let landed = await TestSupport.poll {
            (try? String(contentsOfFile: output, encoding: .utf8))?.hasSuffix(last) == true
        }
        watchdog.cancel()
        await channel.stop()
        let received = (try? String(contentsOfFile: output, encoding: .utf8)) ?? ""
        let sizes = "sent \(text.utf8.count) bytes, received \(received.utf8.count)"
        #expect(landed, Comment(rawValue: sizes + "; starts: " + received.prefix(40)))
        #expect(received == text)
    }
}
