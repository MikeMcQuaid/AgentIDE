@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct QuarantineTests {
    @Test
    func `clears the attribute from the agents install`() throws {
        let root = try TestSupport.temporaryDirectory("quarantine")
        let cask = root + "/cask/bin"
        let binaries = root + "/bin"
        try FileManager.default.createDirectory(atPath: cask, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: binaries, withIntermediateDirectories: true)
        for name in ["codex", "codex-helper", "clean"] {
            try "".write(toFile: cask + "/" + name, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(atPath: binaries + "/codex", withDestinationPath: cask + "/codex")
        let marker = "0083;00000000;test;"
        for name in ["codex", "codex-helper"] {
            let marked = marker.withCString { value in
                setxattr(cask + "/" + name, "com.apple.quarantine", value, marker.utf8.count, 0, 0) == 0
            }
            try #require(marked)
        }

        let cleared = Quarantine.clear(for: .codexCLI, binaryDirectories: [binaries])

        let real = URL(filePath: cask).resolvingSymlinksInPath().path
        #expect(cleared == [real + "/codex", real + "/codex-helper"])
        #expect(getxattr(cask + "/codex-helper", "com.apple.quarantine", nil, 0, 0, 0) < 0)
        #expect(Quarantine.clear(for: .codexCLI, binaryDirectories: [binaries]).isEmpty)
        #expect(Quarantine.clear(for: .claudeCode, binaryDirectories: [binaries]).isEmpty)
    }
}
