@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - HerdrWaitTests

/// The waiter asks herdr for every state but the one the agent is
/// in, so any change answers it.
struct HerdrWaitTests {
    @Test
    func `waiting for a change names every other state`() async {
        let runner = RecordingRunner()
        let herdr = HerdrClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            configHome: "/tmp/herdr-wait-test",
        )
        #expect(await herdr.waitForAgentChange(paneID: "w1:p1", from: .working, timeoutMilliseconds: 10))
        let command = try? #require(runner.commands.last)
        #expect(command?.contains("w1:p1") == true)
        let states = zip(command ?? [], (command ?? []).dropFirst())
            .filter { $0.0 == "--until" }
            .map(\.1)
        #expect(states == ["idle", "blocked", "done"])

        _ = await herdr.waitForAgentChange(paneID: "w1:p1", from: nil, timeoutMilliseconds: 10)
        let all = zip(runner.commands.last ?? [], (runner.commands.last ?? []).dropFirst())
            .filter { $0.0 == "--until" }
            .map(\.1)
        #expect(all == ["working", "idle", "blocked", "done"])
    }
}
