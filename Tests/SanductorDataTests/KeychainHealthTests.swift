import Foundation
@testable import SanductorData
import Testing

/// The sandbox keychain check: what the probe asks and what it
/// advises.
struct KeychainHealthTests {
    @Test
    func `a locked dedicated keychain never triggers a credential lookup`() async throws {
        let root = try TestSupport.temporaryDirectory("keychain")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/Library/Keychains", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root + "/Library/Keychains/login.keychain-db", contents: nil)
        let script = "security() { [[ \"${1}\" == find-generic-password ]] && touch "
            + (root + "/looked-up").shellQuoted + "; return 1; }; "
            + KeychainHealth.probe.replacing("${HOME}", with: root)
        let result = try await TestSupport.run(TestSupport.sudoLoginArguments(["/bin/zsh", "-fc", script]))
        #expect(result.standardOutput.contains("legacy-locked"))
        #expect(FileManager.default.fileExists(atPath: root + "/looked-up") == false)
    }

    @Test
    func `only a shut legacy keychain still holding credentials earns advice`() {
        let advice = KeychainHealth.advice(
            from: "legacy-locked\n",
            sandboxUser: "sandvault-mike",
            sandboxHome: "/Users/sandvault-mike",
        )
        #expect(advice?.contains("`sv build --rebuild`") == true)
        #expect(advice?.contains("rm /Users/sandvault-mike/Library/Keychains/login.keychain-db") == true)
        #expect(advice?.contains("`sv claude`") == true)
        for answer in ["no-legacy\n", "legacy-opens\n", "migrated\n", "", "zsh: command not found: security\n"] {
            let quiet = KeychainHealth.advice(
                from: answer,
                sandboxUser: "sandvault-mike",
                sandboxHome: "/Users/sandvault-mike",
            )
            #expect(quiet == nil)
        }
    }

    @Test
    func `the probe never looks a shut keychain up`() {
        // A lookup in a keychain that will not open raises the very
        // dialog the check exists to warn about.
        let lookups = KeychainHealth.probe.components(separatedBy: "find-generic-password")
        #expect(lookups.count == 2)
        #expect(lookups[1].contains("${own}"))
        #expect(lookups[1].contains("${legacy}") == false)
        #expect(KeychainHealth.probe.contains("unlock-keychain -p '' \"${legacy}\""))
    }
}
