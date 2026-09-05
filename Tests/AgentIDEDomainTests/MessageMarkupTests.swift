@testable import AgentIDEDomain
import Testing

/// What the messages pane draws monospaced, and what it leaves as
/// prose.
struct MessageMarkupTests {
    @Test
    func `a span in backticks is drawn without them`() {
        let rendered = MessageMarkup.rendered("Pushed `non-capturing-regexp-groups`.")
        #expect(rendered.text == "Pushed non-capturing-regexp-groups.")
        #expect(rendered.code.count == 1)
        #expect(rendered.text[rendered.code[0]] == "non-capturing-regexp-groups")
    }

    @Test
    func `every span is found, and a lone backtick is prose`() {
        let rendered = MessageMarkup.rendered("Rebased `feature` on `origin/main`.")
        #expect(rendered.text == "Rebased feature on origin/main.")
        #expect(rendered.code.map { String(rendered.text[$0]) } == ["feature", "origin/main"])

        // Nothing closes it, so nothing is marked and the message
        // reads exactly as it was written.
        let unclosed = MessageMarkup.rendered("A stray ` tick")
        #expect(unclosed.text == "A stray ` tick")
        #expect(unclosed.code.isEmpty)
    }

    @Test
    func `a message with no markup is left alone`() {
        let rendered = MessageMarkup.rendered("The network is back; pull request state is refreshing.")
        #expect(rendered.text == "The network is back; pull request state is refreshing.")
        #expect(rendered.code.isEmpty)
    }
}
