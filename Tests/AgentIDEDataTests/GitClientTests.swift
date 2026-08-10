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

    @Test
    func `changed lines parse hunk headers including pure deletions`() {
        let diff = """
        diff --git a/f b/f
        @@ -1,2 +1,3 @@
        @@ -10 +12 @@
        @@ -20,3 +22,0 @@
        """

        let lines = GitClient.changedLines(fromUnifiedDiff: diff)

        #expect(lines == Set([1, 2, 3, 12, 22]))
    }
}
