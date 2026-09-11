import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// The channel's reading must not wait on any other channel: a pane
/// whose client sits silent (an idle agent) is the normal case, and
/// a fresh attach beside it has to draw at once.
struct HerdrTerminalChannelReaderTests {
    @Test
    func `a fresh client is read while other clients stay silent`() async throws {
        let silent = (0 ..< 3).map { _ in HerdrTerminalChannel(command: ["sleep", "300"]) }
        var drains = [Task<Void, Never>]()
        for channel in silent {
            let stream = try await channel.start()
            drains.append(Task {
                // Drained the way a pane drains its client.
                for await _ in stream {
                    // Nothing to keep.
                }
            })
        }
        let closed = #"{"type":"terminal.closed","reason":"done"}"#
        let live = HerdrTerminalChannel(command: ["sh", "-c", "printf '%s\\n' '" + closed + "'; sleep 300"])
        let stream = try await live.start()
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await event in stream {
                    if case .closed = event {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        // Awaited, so no `sleep` child outlives the test.
        await live.stop()
        for channel in silent {
            await channel.stop()
        }
        for drain in drains {
            drain.cancel()
        }
        #expect(arrived, "the live client's first line should arrive while three clients say nothing")
    }
}
