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
        metadata.agentVersions["session"] = "2.1.239"
        store.save(metadata)

        let loaded = store.load()
        #expect(loaded.prompts["session"] == "prompt")
        #expect(loaded.arguments["session"] == "--model fable")
        #expect(loaded.resumeIDs["session"] == "abc")
        #expect(loaded.sessionsByWorktree["/w"] == "session")
        #expect(loaded.lastSeen["session"] == seen)
        // The tolerant decoder once skipped this field, so every
        // reload silently dropped the recorded versions and the
        // session strip never showed one.
        #expect(loaded.agentVersions["session"] == "2.1.239")
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
    func `saving evicts the oldest cache entries beyond each cap`() throws {
        let root = try TestSupport.temporaryDirectory("store-caps")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")

        var metadata = AppMetadata()
        for age in 0 ... 80 {
            metadata.conversationCache["conversation-\(age)"] =
                CachedConversation(savedAt: Date(timeIntervalSince1970: TimeInterval(age)))
        }
        for age in 0 ... 40 {
            metadata.pullRequestListsCache["listing-\(age)"] =
                CachedPullRequestList(summaries: [], savedAt: Date(timeIntervalSince1970: TimeInterval(age)))
        }
        store.save(metadata)

        let loaded = store.load()
        #expect(loaded.conversationCache.count == 80)
        #expect(loaded.conversationCache["conversation-0"] == nil)
        #expect(loaded.conversationCache["conversation-80"] != nil)
        #expect(loaded.pullRequestListsCache.count == 40)
        #expect(loaded.pullRequestListsCache["listing-0"] == nil)
        #expect(loaded.pullRequestListsCache["listing-40"] != nil)
    }

    @Test
    func `round trips the cached sidebar snapshot`() throws {
        let root = try TestSupport.temporaryDirectory("store-cache")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")

        var repository = CachedRepository()
        repository.name = "AgentIDE"
        repository.fullName = "octocat/example"
        repository.path = "/r"
        var worktree = CachedWorktree()
        worktree.branch = "agent/fix"
        worktree.path = "/w"
        repository.worktrees = [worktree]
        var metadata = AppMetadata()
        metadata.cachedSidebar = [repository]
        store.save(metadata)

        let cached = store.load().cachedSidebar
        #expect(cached.first?.fullName == "octocat/example")
        #expect(cached.first?.worktrees.first?.branch == "agent/fix")
    }
}
