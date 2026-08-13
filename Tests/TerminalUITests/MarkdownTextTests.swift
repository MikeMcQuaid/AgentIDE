@testable import TerminalUI
import Testing

/// Exercises the markdown parsing feeding the one markdown view.
@MainActor
struct MarkdownTextTests {
    @Test
    func `consecutive prose lines merge into one selectable block`() {
        let markdown = """
        First line
        second line

        another paragraph
        # Heading
        | a | b |
        | - | - |
        | 1 | 2 |
        """
        let blocks = MarkdownText.proseBlocks(markdown)
        #expect(blocks.count == 3)
        if case let .text(text) = blocks[0] {
            #expect(text == "First line\nsecond line\n\nanother paragraph")
        } else {
            Issue.record("The prose lines should merge into one text block")
        }
        if case let .heading(title) = blocks[1] {
            #expect(title == "Heading")
        } else {
            Issue.record("The heading should end the text block")
        }
        if case let .table(header, rows)? = blocks.last {
            #expect(header == ["a", "b"])
            #expect(rows == [["1", "2"]])
        } else {
            Issue.record("The pipe rows should parse as a table")
        }
    }
}
