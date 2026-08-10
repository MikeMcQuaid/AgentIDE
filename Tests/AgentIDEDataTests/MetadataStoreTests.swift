import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the metadata file round trip.
struct MetadataStoreTests {
    @Test
    func `round trips every field and tolerates a missing file`() throws {
        let root = try TestSupport.temporaryDirectory("store")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/nested/state.json")

        #expect(store.load().prompts.isEmpty)

        let seen = Date(timeIntervalSince1970: 1)
        var metadata = AppMetadata()
        metadata.lastSeen["session"] = seen
        metadata.prompts["session"] = "prompt"
        metadata.arguments["session"] = "--model fable"
        metadata.resumeIDs["session"] = "abc"
        metadata.sessionsByWorktree["/w"] = "session"
        store.save(metadata)

        let loaded = store.load()
        #expect(loaded.prompts["session"] == "prompt")
        #expect(loaded.arguments["session"] == "--model fable")
        #expect(loaded.resumeIDs["session"] == "abc")
        #expect(loaded.sessionsByWorktree["/w"] == "session")
        #expect(loaded.lastSeen["session"] == seen)
    }

    @Test
    func `decoding tolerates files written before new fields existed`() throws {
        let root = try TestSupport.temporaryDirectory("store-old")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/state.json"
        try #"{"prompts":{"session":"keep me"}}"#.write(toFile: file, atomically: true, encoding: .utf8)

        let loaded = MetadataStore(file: file).load()
        #expect(loaded.prompts["session"] == "keep me")
        #expect(loaded.cachedSidebar.isEmpty)
        #expect(loaded.sessionsByWorktree.isEmpty)
    }

    @Test
    func `round trips the cached sidebar snapshot`() throws {
        let root = try TestSupport.temporaryDirectory("store-cache")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")

        var repository = CachedRepository()
        repository.name = "AgentIDE"
        repository.fullName = "MikeMcQuaid/AgentIDE"
        repository.path = "/r"
        var worktree = CachedWorktree()
        worktree.branch = "agent/fix"
        worktree.path = "/w"
        repository.worktrees = [worktree]
        var metadata = AppMetadata()
        metadata.cachedSidebar = [repository]
        store.save(metadata)

        let cached = store.load().cachedSidebar
        #expect(cached.first?.fullName == "MikeMcQuaid/AgentIDE")
        #expect(cached.first?.worktrees.first?.branch == "agent/fix")
    }
}
