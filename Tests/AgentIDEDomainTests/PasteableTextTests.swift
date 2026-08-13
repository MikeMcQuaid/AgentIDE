import AgentIDEDomain
import Testing

/// Exercises the copy reflow that makes terminal yanks paste
/// cleanly into prose tools.
struct PasteableTextTests {
    @Test
    func `joins hard-wrapped lines and keeps paragraphs apart`() {
        let wrapped = """
          The agent finished the refactor and moved the tests
          into their own target so they run in parallel.

          A second paragraph survives the reflow.
        """
        #expect(
            PasteableText.reflow(wrapped) == "The agent finished the refactor and moved the tests "
                + "into their own target so they run in parallel."
                + "\n\nA second paragraph survives the reflow.",
        )
    }

    @Test
    func `list items keep their own lines and swallow their wraps`() {
        let list = """
        Changes:
        - first item wraps onto
          a second terminal line
        - second item
        1. numbered too
        """
        #expect(
            PasteableText.reflow(list) == "Changes:"
                + "\n\n- first item wraps onto a second terminal line"
                + "\n- second item"
                + "\n1. numbered too",
        )
    }

    @Test
    func `single lines only lose surrounding whitespace`() {
        #expect(PasteableText.reflow("  one line  ") == "one line")
        #expect(PasteableText.reflow("  git status  \n") == "git status")
    }

    @Test
    func `gutter marks trim from lines and single copies`() {
        #expect(PasteableText.strippingGutter("\u{258E} hello") == "hello")
        #expect(PasteableText.strippingGutter("\u{258E}\u{258E} nested") == "nested")
        #expect(PasteableText.reflow("\u{258E} first line\n\u{258E} second line") == "first line second line")
        #expect(PasteableText.reflow("  \u{258E} one liner  ") == "one liner")
    }

    @Test
    func `blank runs collapse to one paragraph break`() {
        #expect(PasteableText.reflow("a\n\n\n\nb") == "a\n\nb")
    }
}
