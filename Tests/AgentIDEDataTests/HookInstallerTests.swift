import AgentIDEData
import Foundation
import Testing

/// Exercises hook installation against a temporary template
/// directory: idempotency and coexistence with third-party hooks.
struct HookInstallerTests {
    @Test
    func `installs alongside existing hooks exactly once`() throws {
        let root = try TestSupport.temporaryDirectory("hooks")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root,
            sandboxHome: root + "/home",
            archivesDirectory: root + "/archives",
            metadataFile: root + "/state.json",
        )
        let settingsPath = paths.userTemplateDirectory + "/.claude/settings.json"
        try FileManager.default.createDirectory(
            atPath: paths.userTemplateDirectory + "/.claude",
            withIntermediateDirectories: true,
        )
        let existing = """
        {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "third-party-notify"}]}]}}
        """
        try existing.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let installer = HookInstaller(paths: paths)
        try installer.ensureInstalled()
        try installer.ensureInstalled()

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        for event in HookInstaller.events {
            let entries = try #require(hooks[event] as? [[String: Any]], "missing \(event)")
            let commands = entries.flatMap { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
            let installed = commands.count { $0.contains("agentide-notify") }
            #expect(installed == 1)
            if event == "Stop" {
                #expect(commands.contains("third-party-notify"))
            }
        }

        let script = paths.userTemplateDirectory + "/.claude/agentide-notify.sh"
        #expect(FileManager.default.isExecutableFile(atPath: script))
    }
}
