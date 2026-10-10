import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownHTMLTests {
    @Test
    func `bot HTML formatting and entities become readable Markdown`() {
        let source = """
        - [ ] <strong title="Keep fixing > findings">Autopilot</strong> · Keep fixing
        <sub>Comment <code>@coderabbitai help</code> for commands &amp; options.</sub>
        <blockquote><p><em>Check</em> <del>old code</del>.</p></blockquote>
        """
        let result = MarkdownText.strippingHTML(source)
        #expect(result.contains("**Autopilot**"))
        #expect(result.contains("`@coderabbitai help`"))
        #expect(result.contains("commands & options"))
        #expect(result.contains("*Check* ~~old code~~"))
        #expect(result.contains("<") == false)
    }

    @Test
    func `nested bot disclosures retain their own summaries and trailing content`() throws {
        let source = """
        <details><summary>Review <strong>details</strong></summary>
        Before
        <blockquote><details><summary>file.swift (1)</summary>
        Finding
        </details></blockquote>
        After
        </details>
        Tail
        """
        let chunks = MarkdownText.parsedChunks(source)
        let outer = try #require(chunks.first)
        #expect(outer.detailsSummary == "Review **details**")
        #expect(outer.text.contains("After"))
        let nested = MarkdownText.parsedChunks(outer.text)
        #expect(nested.contains { $0.detailsSummary == "file.swift (1)" && $0.text.contains("Finding") })
        #expect(chunks.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Tail")
    }

    @Test
    func `code examples keep literal HTML and do not become disclosures`() {
        let source = """
        Inline `<strong>literal</strong>`.

        ```html
        <details><summary>Example</summary><script>literal()</script></details>
        ```
        """
        let chunks = MarkdownText.parsedChunks(source)
        #expect(chunks.allSatisfy { $0.detailsSummary == nil })
        #expect(MarkdownText.strippingHTML(source) == source)
    }

    @Test
    func `unicode and many code spans keep their original contents`() {
        let source = (0 ..< 12).lazy.map { "Révision 🐰 `value<\($0)>`" }.joined(separator: "\n\n")
            + "\n\n[link](https://example.com/?a=1&b=2) <https://example.com/>"
        #expect(MarkdownText.strippingHTML(source) == source)
    }

    @Test
    func `disclosures preserve fenced examples and their comment markers`() throws {
        let code = """
        ```html
        <strong>Example</strong>
        [//]: # (a literal comment)
        ```
        """
        let source = "<details><summary>Examples</summary>\n\n" + code + "\n\n</details>"
        let chunk = try #require(MarkdownText.parsedChunks(source).first)
        #expect(chunk.detailsSummary == "Examples")
        #expect(MarkdownText.strippingHTML(chunk.text).contains(code))
    }

    @Test
    func `quoted review paragraphs stay separate`() throws {
        let source = "<blockquote><p>First finding.</p><p>Second finding.</p></blockquote>"
        let block = try #require(MarkdownText.proseBlocks(MarkdownText.strippingHTML(source)).first)
        guard case let .quote(text) = block else {
            Issue.record("The HTML quote should render as a native Markdown quote")
            return
        }

        #expect(text == "First finding.\n\nSecond finding.")
    }

    @Test
    func `formatting leaves tables and tasks structured and omits executable elements`() {
        let source = """
        | File | Status |
        | --- | --- |
        | `file.swift` | <strong>Fixed</strong> |

        - [x] <strong>Review</strong>

        <script>bad()</script><style>body { color: red }</style>
        <blockquote><p>Check <a href="https://example.com">the finding</a>.</p></blockquote>
        """
        let markdown = MarkdownText.strippingHTML(source)
        #expect(markdown.contains("bad()") == false)
        #expect(markdown.contains("color: red") == false)
        #expect(MarkdownText.ticked(markdown).contains("☑ **Review**"))
        let blocks = MarkdownText.proseBlocks(markdown)
        #expect(blocks.contains { block in
            if case let .table(header, rows) = block {
                return header == ["File", "Status"] && rows == [["`file.swift`", "**Fixed**"]]
            }
            return false
        })
        #expect(blocks.contains { block in
            if case let .quote(text) = block {
                return text.contains("[the finding](https://example.com)")
            }
            return false
        })
    }
}
