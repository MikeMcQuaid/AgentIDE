@testable import AgentIDERemote
import Foundation
@testable import MobileFeature
import NIOCore
import NIOPosix
import Testing

struct MobileSubscriptionTests {
    // MARK: Internal

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func `opening subscriptions respect pane changes and cancellation`(changed: Bool, cancelled: Bool) async throws {
        let first = try await channel()
        defer { first.close(promise: nil) }
        let second = try await channel()
        defer { second.close(promise: nil) }
        let output = AsyncThrowingStream<Data, Error> { $0.finish() }
        let model = MobileModel(configuration: SSHConfiguration())
        model.eventPaneIDs = ["p1"]
        var opening: CheckedContinuation<SSHCommand, Never>?
        var requested = [[String]]()
        var received = [[String]]()
        let task = Task {
            try await model.subscribe(open: { panes in
                requested.append(panes)
                if requested.count == 1 {
                    return await withCheckedContinuation { opening = $0 }
                }
                return SSHCommand(channel: second, output: output)
            }, receive: { _ in received.append(requested.last ?? []) })
        }
        while opening == nil {
            await Task.yield()
        }
        if changed {
            model.eventPaneIDs = ["p1", "p2"]
            model.resubscribe = true
            model.eventChannel?.close()
        }
        if cancelled {
            task.cancel()
        }
        opening?.resume(returning: SSHCommand(channel: first, output: output))
        if cancelled {
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await #expect(throws: RemoteError.self) { try await task.value }
        }
        #expect(requested == (changed && cancelled == false ? [["p1"], ["p1", "p2"]] : [["p1"]]))
        #expect(received == (cancelled ? [] : [model.eventPaneIDs]))
        try await first.closeFuture.get()
        if changed, cancelled == false {
            try await second.closeFuture.get()
        }
    }

    // MARK: Private

    private func channel() async throws -> any Channel {
        try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }
}
