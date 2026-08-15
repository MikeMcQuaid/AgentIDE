@testable import TerminalUI
import Testing

/// Exercises the markdown parsing feeding the one markdown view.
@MainActor
struct MarkdownTextTests {
    @Test
    func `html lists, code spans and comment markers become markdown`() {
        let body = """
        [//]: # (dependabot-automerge-start)
        <ul>
        <li><code>55cc834</code> Merge pull request #1768</li>
        <li>Additional commits viewable in compare view</li>
        </ul>
        [//]: # (dependabot-automerge-end)
        """
        let stripped = MarkdownText.strippingHTML(body)
        #expect(stripped.contains("- `55cc834` Merge pull request #1768"))
        #expect(stripped.contains("- Additional commits viewable in compare view"))
        #expect(stripped.contains("<") == false)
        #expect(stripped.contains("[//]: #") == false)
    }

    @Test
    func `details tables parse as tables after tag stripping`() {
        let body = """
        <details>
        <summary>Show a summary per file</summary>

        | File | Description |
        | ---- | ----------- |
        | `Sources/a.swift` | Does a thing |

        </details>
        """
        let stripped = MarkdownText.strippingHTML(body)
        let blocks = MarkdownText.proseBlocks(stripped)
        let isTable = blocks.contains { block in
            if case let .table(header, rows) = block {
                return header == ["File", "Description"] && rows.count == 1
            }
            return false
        }
        #expect(isTable)
    }

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
            #expect(text.contains("First line"))
            #expect(text.contains("another paragraph"))
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
