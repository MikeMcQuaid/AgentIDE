import AgentIDEData
import Foundation
import Testing

/// Exercises the FSEvents workspace watcher against real writes.
struct WorkspaceWatcherIntegrationTests {
    // MARK: Internal

    @Test
    func `a write inside a root is remembered as its top directories`() async throws {
        // FSEvents reports physical paths, so the scratch root is
        // resolved before it becomes a watch root.
        let scratch = try TestSupport.temporaryDirectory("watcher")
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let root = URL(fileURLWithPath: scratch).resolvingSymlinksInPath().path + "/repositories"
        try FileManager.default.createDirectory(
            atPath: root + "/brew/Library",
            withIntermediateDirectories: true,
        )

        let watcher = WorkspaceWatcher(roots: [root])
        watcher.start()
        #expect(watcher.isWatching)

        // "Since now" still delivers the directories made a moment
        // ago once the stream opens, the root among them; let those
        // land and drain before the write under test.
        try await Task.sleep(for: .seconds(Self.settleSeconds))
        _ = watcher.consumeChangedPaths()

        try "changed".write(toFile: root + "/brew/Library/file.txt", atomically: true, encoding: .utf8)
        var changed = Set<String>()
        for _ in 0 ..< Self.waitAttempts where changed.isEmpty {
            changed = watcher.consumeChangedPaths()
            try await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }

        // Trimmed to at most two components under the root, so deep
        // churn in one worktree collapses to one entry.
        #expect(changed.isEmpty == false)
        #expect(changed.allSatisfy { $0.hasPrefix(root + "/brew") })

        // Consuming clears; quiet directories stay quiet.
        #expect(watcher.consumeChangedPaths().isEmpty)
    }

    // MARK: Private

    /// Generous: FSEvents delivery on a loaded CI runner can lag
    /// far behind the half-second latency asked for.
    private static let waitAttempts = 240
    private static let pollMilliseconds = 50
    private static let settleSeconds = 2
}
