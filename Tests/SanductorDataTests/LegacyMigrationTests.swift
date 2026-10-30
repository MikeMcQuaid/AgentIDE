import Foundation
@testable import SanductorData
import Testing

struct LegacyMigrationTests {
    @Test
    func `migration merges missing files and preferences without overwriting new state`() throws {
        let root = try TestSupport.temporaryDirectory("legacy-migration")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let domain = "sanductor-migration-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let oldDomain = domain + ".legacy"
        defer { defaults.removePersistentDomain(forName: oldDomain) }
        defaults.setPersistentDomain(["fontSize": 14, "signing": true], forName: oldDomain)
        defaults.setPersistentDomain(["fontSize": 16], forName: domain)
        for (name, value) in [
            (".agentide/conversations/session.jsonl", "conversation"),
            ("Library/Application Support/AgentIDE/state.json", "old state"),
            ("Library/Application Support/AgentIDE/Avatars/user.png", "avatar"),
            ("Library/Application Support/Sanductor/state.json", "new state"),
        ] {
            let path = URL(filePath: root + "/" + name)
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try value.write(to: path, atomically: true, encoding: .utf8)
        }

        try LegacyMigration.run(home: root, defaults: defaults, domain: domain, legacyDomain: oldDomain)

        #expect(defaults.integer(forKey: "fontSize") == 16)
        #expect(defaults.bool(forKey: "signing"))
        #expect(try String(contentsOfFile: root + "/.sanductor/conversations/session.jsonl", encoding: .utf8)
            == "conversation")
        #expect(try String(contentsOfFile: root + "/Library/Application Support/Sanductor/state.json", encoding: .utf8)
            == "new state")
        #expect(FileManager.default.fileExists(
            atPath: root + "/Library/Application Support/Sanductor/Avatars/user.png",
        ))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root + "/.agentide") == ".sanductor")
        try "later".write(
            toFile: root + "/Library/Application Support/AgentIDE/later", atomically: true, encoding: .utf8,
        )
        try LegacyMigration.run(home: root, defaults: defaults, domain: domain, legacyDomain: oldDomain)
        #expect(FileManager.default.fileExists(atPath: root + "/Library/Application Support/Sanductor/later") == false)
    }

    @Test
    func `an unsafe destination fails without marking the migration complete`() throws {
        let root = try TestSupport.temporaryDirectory("legacy-migration-link")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let domain = "sanductor-migration-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try FileManager.default.createDirectory(atPath: root + "/.agentide", withIntermediateDirectories: true)
        try "private".write(toFile: root + "/.agentide/file", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: root + "/outside", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/.sanductor", withDestinationPath: root + "/outside")
        #expect(throws: (any Error).self) {
            try LegacyMigration.run(home: root, defaults: defaults, domain: domain)
        }
        #expect(FileManager.default.fileExists(atPath: root + "/outside/file") == false)
        try FileManager.default.removeItem(atPath: root + "/.sanductor")
        try LegacyMigration.run(home: root, defaults: defaults, domain: domain)
        #expect(try String(contentsOfFile: root + "/.sanductor/file", encoding: .utf8) == "private")
    }
}
