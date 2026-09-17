@testable import AgentIDEData
import Foundation
import Testing

/// The sandbox keychain check: what the probe asks and what it
/// advises.
struct KeychainHealthTests {
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
        #expect(lookups[1].contains("$own"))
        #expect(lookups[1].contains("$legacy") == false)
        #expect(KeychainHealth.probe.contains("unlock-keychain -p '' \"$legacy\""))
    }
}
