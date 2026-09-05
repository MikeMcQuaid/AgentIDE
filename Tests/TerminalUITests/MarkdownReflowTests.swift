@testable import TerminalUI
import Testing

/// Prose wrapped the way GitHub wraps it, and an image drawn rather
/// than dropped.
struct MarkdownReflowTests {
    @Test
    func `a soft break inside a paragraph joins rather than wraps`() {
        let wrapped = """
        A paragraph an editor wrapped
        at some column of its own.

        The next paragraph.
        """

        #expect(MarkdownText.reflowed(wrapped) == """
        A paragraph an editor wrapped at some column of its own.

        The next paragraph.
        """)
    }

    @Test
    func `structure keeps its own lines`() {
        let source = """
        - one item
        - another item
          carrying on
        # A heading
        | a | b |
        """

        // List items stay their own; a line continuing one joins it.
        #expect(MarkdownText.reflowed(source) == """
        - one item
        - another item carrying on
        # A heading
        | a | b |
        """)
    }

    @Test
    func `a break the author asked for is kept`() {
        // Two trailing spaces and a backslash are markdown's own
        // hard breaks.
        #expect(MarkdownText.reflowed("first line  \nsecond") == "first line  \nsecond")
        #expect(MarkdownText.reflowed("first line\\\nsecond") == "first line\\\nsecond")
    }

    @Test
    func `an image source points at the web or at this Mac`() {
        #expect(MarkdownText.imageURL("https://example.invalid/a.png")?.scheme == "https")
        #expect(MarkdownText.imageURL("/tmp/a.png")?.isFileURL == true)
        // Nothing to be relative to, so it stays alt text.
        #expect(MarkdownText.imageURL("docs/screenshot.png") == nil)
    }
}
