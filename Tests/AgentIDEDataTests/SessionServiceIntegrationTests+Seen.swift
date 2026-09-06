import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// When a worktree's activity counts as seen, and when the seen
/// time is written. Split from the service's tests for length.
extension SessionServiceIntegrationTests {
    @Test
    func `the selected worktree is seen as it is read, and written down only then`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let defaults = UserDefaults.standard
        let selectedBefore = defaults.string(forKey: "selectedWorktreePath")
        defer { defaults.set(selectedBefore, forKey: "selectedWorktreePath") }

        // Activity: a transcript newer than anything seen.
        let directory = try #require(PromptCaptureRunner().transcriptDirectory(
            workingDirectory: path,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let line = #"{"type":"user","message":{"content":[{"type":"text","text":"new"}]}}"# + "\n"
        // Modification times are read to the whole second, and the
        // service started this second: written after the next one
        // begins, the transcript is newer than that start without
        // being in the future, which nothing real ever is.
        try await Task.sleep(for: .seconds(1.2))
        try line.write(toFile: directory + "/fresh.jsonl", atomically: true, encoding: .utf8)
        let store = MetadataStore(file: world.paths.metadataFile)

        // Not on screen: unread, and nothing is written about it.
        defaults.set("/somewhere/else", forKey: "selectedWorktreePath")
        let elsewhere = await world.service.overview()
        #expect(elsewhere.groups.first?.items.first { $0.worktree.path == path }?.hasUnread == true)
        #expect(store.load().seenAt[path] == nil)

        // On screen: seen as it is read, once, and the reading says
        // so without a second pass.
        defaults.set(path, forKey: "selectedWorktreePath")
        let shown = await world.service.overview()
        #expect(shown.groups.first?.items.first { $0.worktree.path == path }?.hasUnread == false)
        let written = try #require(store.load().seenAt[path])

        // Nothing new: read again, nothing rewritten.
        _ = await world.service.overview()
        #expect(store.load().seenAt[path] == written)
    }

    @Test
    func `a model cache names the client that wrote it`() {
        let cache = Data(#"{"client_version": "0.152.1", "fetched_at": "2026-09-06T16:04:41Z", "models": []}"#.utf8)
        #expect(SessionService.clientVersion(inModelCache: cache) == "0.152.1")
        #expect(SessionService.clientVersion(inModelCache: Data("{}".utf8)) == nil)
        #expect(SessionService.clientVersion(inModelCache: Data("not json".utf8)) == nil)
    }
}
