@testable import AgentIDEDomain
import Testing

/// Reading a Claude alias's version out of the identifiers Claude
/// Code has used, rather than out of a list written by hand.
struct ClaudeModelNamesTests {
    @Test
    func `an identifier's version becomes the alias's name`() {
        let names = ClaudeModelNames.names(fromIdentifiers: [
            "claude-fable-5-1[1m]",
            "claude-opus-5",
            "claude-haiku-4-5-20251001",
        ])

        // The release date some identifiers carry is not a version,
        // and the context marker is not part of the name.
        #expect(names["fable"] == "Fable 5.1")
        #expect(names["opus"] == "Opus 5")
        #expect(names["haiku"] == "Haiku 4.5")
    }

    @Test
    func `the newest version of a family wins`() {
        let names = ClaudeModelNames.names(fromIdentifiers: [
            "claude-fable-5",
            "claude-fable-5-1",
            "claude-opus-4-8",
            "claude-opus-5",
        ])

        #expect(names["fable"] == "Fable 5.1")
        #expect(names["opus"] == "Opus 5")
    }

    @Test
    func `an identifier it cannot read contributes nothing`() {
        // Nothing is guessed at: an alias no identifier names keeps
        // whatever the picker would have shown for it.
        #expect(ClaudeModelNames.names(fromIdentifiers: ["gpt-5.6-sol", "claude", "claude-code-setup"]).isEmpty)
    }
}
