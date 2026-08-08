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

        #expect(store.load().archives.isEmpty)

        let seen = Date(timeIntervalSince1970: 1)
        var metadata = AppMetadata()
        metadata.lastSeen["session"] = seen
        metadata.prompts["session"] = "prompt"
        metadata.arguments["session"] = "--model fable"
        metadata.resumeIDs["session"] = "abc"
        metadata.archives.append(ArchiveMetadata(
            id: "id",
            repositoryName: "repo",
            repositoryPath: "/r",
            branch: "b",
            worktreePath: "/w",
            sessionName: "session",
            resumeID: "abc",
            archivedAt: Date(timeIntervalSince1970: 2),
        ))
        store.save(metadata)

        let loaded = store.load()
        #expect(loaded.prompts["session"] == "prompt")
        #expect(loaded.arguments["session"] == "--model fable")
        #expect(loaded.resumeIDs["session"] == "abc")
        #expect(loaded.archives.first?.branch == "b")
        #expect(loaded.lastSeen["session"] == seen)
    }
}
