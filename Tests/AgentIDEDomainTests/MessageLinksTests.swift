import AgentIDEDomain
import Testing

/// The links a message carries, which the messages pane makes
/// clickable rather than leaving to be copied out by hand.
struct MessageLinksTests {
    @Test
    func `web links are found and anything else is left alone`() throws {
        let message = "Opened pull request https://github.com/Homebrew/brew/pull/23670 for this"
        let found = MessageLinks.links(in: message)

        #expect(found.count == 1)
        #expect(found.first?.url.absoluteString == "https://github.com/Homebrew/brew/pull/23670")
        #expect(try String(message[#require(found.first).range]).hasPrefix("https://github.com"))

        // A path, a branch name and an address with no scheme are
        // not links: a message is command output as often as prose.
        #expect(MessageLinks.links(in: "/Users/Shared/sv-mike/worktrees/brew/main").isEmpty)
        #expect(MessageLinks.links(in: "Rebased relocate-build-prefix-hardening.").isEmpty)
    }
}
