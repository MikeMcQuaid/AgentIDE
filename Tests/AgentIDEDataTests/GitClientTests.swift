import AgentIDEData
import Foundation
import Testing

struct GitClientTests {
    @Test
    func `repository listing skips symlinked aliases and plain directories`() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("agentide-repos-" + UUID().uuidString)
            .path
        try manager.createDirectory(atPath: root + "/real/.git", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/plain", withIntermediateDirectories: true)
        try manager.createSymbolicLink(atPath: root + "/alias", withDestinationPath: root + "/real")
        defer { try? manager.removeItem(atPath: root) }

        let repositories = GitClient(runner: FoundationProcessRunner()).repositories(under: root)

        #expect(repositories.map(\.name) == ["real"])
    }
}
