@testable import TerminalUI
import Testing

@MainActor
struct MarkdownHTMLCodeTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func `code ranges follow Markdown line endings`(_ newline: String) throws {
        let source = ["Intro", "`<strong>literal</strong>`"].joined(separator: newline)
        let protected = try MarkdownHTMLCode(source)
        #expect(protected.restore(protected.source) == source)
        #expect(protected.source.contains("<strong>") == false)
        #expect(MarkdownText.parsedChunks(source).allSatisfy { $0.detailsSummary == nil })
        #expect(MarkdownText.strippingHTML(source).contains("`<strong>literal</strong>`"))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func `nested review content preserves code links and Unicode`(_ newline: String) throws {
        let source = """
        <details><summary>Review</summary>

        > Révision 🐰
        >
        > - Keep `<value>` literal.

        | File | Note |
        | --- | --- |
        | `file.swift` | `a<b>` |

        ```html
        <strong>example</strong>
        ```

        [Documentation](https://example.com/?a=1&b=2)

        </details>
        """.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: newline)
        let protected = try MarkdownHTMLCode(source)
        #expect(protected.restore(protected.source) == source)
        let chunk = try #require(MarkdownText.parsedChunks(source).first)
        #expect(chunk.detailsSummary == "Review")
        let markdown = MarkdownText.strippingHTML(chunk.text)
        #expect(markdown.contains("Révision 🐰"))
        #expect(markdown.contains("`<value>`"))
        #expect(markdown.contains("`a<b>`"))
        #expect(markdown.contains("<strong>example</strong>"))
        #expect(markdown.contains("[Documentation](https://example.com/?a=1&b=2)"))
    }

    @Test
    func `mixed line endings and multiline code retain their original bytes`() throws {
        let source = "\r\nIntro\r`<first>`\n\n`second\r\n<value>`\r\n\r\n```html\r<last>\n```"
        let protected = try MarkdownHTMLCode(source)
        #expect(protected.restore(protected.source) == source)
        #expect(protected.source.contains("<") == false)
    }

    @Test
    func `invalid parser ranges fall back to the original text`() {
        let source = "\0`<value>`"
        #expect(throws: (any Error).self) { try MarkdownHTMLCode(source) }
        #expect(MarkdownText.strippingHTML(source) == source)
        #expect(MarkdownText.parsedChunks(source).first?.text == source)
    }
}
