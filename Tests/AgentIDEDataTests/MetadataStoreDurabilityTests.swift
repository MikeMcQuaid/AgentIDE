import AgentIDEData
import Foundation
import Testing

struct MetadataStoreDurabilityTests {
    @Test
    func `a failed write leaves memory unchanged so a later attempt retries`() throws {
        let root = try TestSupport.temporaryDirectory("store-failed-write")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let parent = root + "/parent"
        try "file blocks directory".write(toFile: parent, atomically: true, encoding: .utf8)
        let store = MetadataStore(file: parent + "/state.json")
        store.update { $0.prompts["task"] = "saved before launch" }
        #expect(store.load().prompts["task"] == nil)
        try FileManager.default.removeItem(atPath: parent)
        store.update { $0.prompts["task"] = "saved before launch" }
        #expect(FileManager.default.fileExists(atPath: parent + "/state.json"))
    }
}
