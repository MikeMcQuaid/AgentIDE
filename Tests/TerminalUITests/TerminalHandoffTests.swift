import AppKit
import SanductorData
@testable import TerminalUI
import Testing

@MainActor
struct TerminalHandoffTests {
    @Test
    func `an initial attach failure is visible before another attach is tried`() async {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 200))
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        defer { coordinator.tearDown() }
        let channel = HerdrTerminalChannel(command: ["true"])
        let reason = "attach refused " + UUID().uuidString
        coordinator.view = view
        coordinator.channel = channel
        coordinator.handle(.closed(reason: reason), from: channel)
        await withCheckedContinuation { continuation in
            coordinator.onProcessTerminated = { continuation.resume() }
            coordinator.finish(for: channel)
        }
        #expect(view.visibleRowsText(0 ..< view.terminalDimensions.rows).joined().contains(reason))
        #expect(coordinator.heldFailure == reason)
        #expect(coordinator.reattachments == 0)
        #expect(ErrorLog.shared.entries.contains { $0.message.contains(reason) } == false)
    }

    @Test
    func `waiting for frames does not fabricate a client exit`() async throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        defer { coordinator.tearDown() }
        let channel = HerdrTerminalChannel(command: ["true"])
        coordinator.view = view
        coordinator.channel = channel
        coordinator.requestInitialState(of: view)
        try await Task.sleep(for: .seconds(6))
        #expect(coordinator.channel === channel)
        #expect(view.visibleRowsText(0 ..< view.terminalDimensions.rows)
            .joined()
            .contains("herdr client exited") == false)
    }

    @Test
    func `a takeover preserves the exit notification for the next controller`() async {
        var exits = 0
        let coordinator = TerminalRepresentable.Coordinator { exits += 1 }
        defer { coordinator.tearDown() }
        let first = HerdrTerminalChannel(command: ["true"])
        coordinator.channel = first
        coordinator.handle(.closed(reason: "terminal attach taken over"), from: first)
        coordinator.finish(for: first)
        #expect(exits == 0)
        #expect(coordinator.onProcessTerminated != nil)

        let second = HerdrTerminalChannel(command: ["true"])
        coordinator.channel = second
        coordinator.framesSeen = 1
        coordinator.handle(.closed(reason: "session exited"), from: second)
        coordinator.finish(for: second)
        for _ in 0 ..< 100 where exits == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(exits == 1)
    }

    @Test
    func `a phone takeover waits for an explicit return instead of retrying`() {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let channel = HerdrTerminalChannel(command: ["true"])
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        coordinator.view = view
        coordinator.channel = channel
        var handedOff = false
        coordinator.onHandoff = { handedOff = $0 }
        coordinator.handle(.closed(reason: "terminal attach taken over"), from: channel)
        #expect(handedOff)
        #expect(coordinator.reattachments == 0)
        #expect(coordinator.heldFailure == nil)
        coordinator.tearDown()
    }

    @Test
    func `reattaching clears handoff before any frame and ignores the old controller`() throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        defer { coordinator.tearDown() }
        var handedOff = false
        coordinator.onHandoff = { handedOff = $0 }
        coordinator.startWhenSized(.control(command: ["/usr/bin/true"]), in: view)
        let first = try #require(coordinator.channel)
        coordinator.handle(.closed(reason: "terminal attach taken over"), from: first)
        #expect(handedOff)
        coordinator.reattach(in: view)
        #expect(handedOff == false)
        #expect(coordinator.channel !== first)
        coordinator.handle(.closed(reason: "terminal attach taken over"), from: first)
        #expect(handedOff == false)
    }
}
