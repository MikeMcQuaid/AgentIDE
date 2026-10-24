import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownHTMLTests {
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
    func `details tables remain structured after tag stripping`() throws {
        let body = """
        <details><summary>Show a summary per file</summary>

        | File | Description |
        | ---- | ----------- |
        | `Sources/a.swift` | Does a thing |

        </details>
        """
        let chunk = try #require(MarkdownText.parsedChunks(body).first)
        #expect(chunk.detailsSummary == "Show a summary per file")
        let content = MarkdownText.content(chunk.text)
        #expect(MarkdownTestSupport.kinds(content).contains(.tableHeaderRow))
        #expect(String(content.characters).contains("Sources/a.swiftDoes a thing"))
    }

    @Test(arguments: ["-1", "1000000000"])
    func `HTML list starts outside the GFM range fall back to one`(start: String) {
        let kinds = MarkdownTestSupport.kinds(
            MarkdownText.content("<ol start=\"" + start + "\"><li>First</li><li>Second</li></ol>"),
        )
        #expect(kinds.contains(.orderedList))
        #expect(kinds.contains(.listItem(ordinal: 2)))
    }

    @Test
    func `HTML ordered lists keep their start and nested lists`() {
        let content = MarkdownText.content("""
        <ol start="3"><li>Third<ul><li>Nested bullet</li></ul></li><li>Fourth</li></ol>
        """)
        #expect(MarkdownTestSupport.kinds(content).contains(.listItem(ordinal: 3)))
        #expect(MarkdownTestSupport.kinds(content).contains(.unorderedList))
    }

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
    func `expanded review headings render bold without literal markers`() throws {
        let source = """
        <details><summary>Recent review info</summary>

        <strong><img src="icon.svg"> Run configuration</strong>

        - Source mode: Auto
        - Repository: Unavailable

        <strong> Commits</strong>

        Reviewing files that changed from the base of the PR.

        <strong> Files selected for processing: 1</strong>

        - Library/Homebrew/test/sample_spec.rb

        </details>
        """
        let chunk = try #require(MarkdownText.parsedChunks(
            ReviewCommentText(source, author: "coderabbitai").text,
        )
        .first)
        let content = MarkdownText.content(chunk.text)
        #expect(String(content.characters).contains("**") == false)
        for heading in ["Run configuration", "Commits", "Files selected for processing: 1"] {
            #expect(content.runs.contains { run in
                String(content[run.range].characters) == heading
                    && run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            })
        }
        #expect(MarkdownTestSupport.kinds(content).contains(.unorderedList))
        #expect(String(content.characters).contains("Source mode: Auto"))
        #expect(String(content.characters).contains("Library/Homebrew/test/sample_spec.rb"))
    }

    @Test(arguments: [
        ("b", "**"), ("strong", "**"), ("em", "*"), ("i", "*"),
        ("del", "~~"), ("s", "~~"), ("strike", "~~"),
    ])
    func `HTML formatting preserves surrounding spaces outside its markers`(tag: String, marker: String) {
        let source = "Before<" + tag + "> styled </" + tag + ">after"
        #expect(MarkdownText.strippingHTML(source) == "Before " + marker + "styled" + marker + " after")
        #expect(String(MarkdownText.content(source).characters) == "Before styled after")
        #expect(MarkdownText.strippingHTML("Before<" + tag + "> </" + tag + ">after") == "Before after")
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
        #expect(outer.detailsSummary == "Review details")
        #expect(outer.text.contains("After"))
        let nested = MarkdownText.parsedChunks(outer.text)
        #expect(nested.contains { $0.detailsSummary == "file.swift (1)" && $0.text.contains("Finding") })
        #expect(chunks.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Tail")
    }

    @Test
    func `disclosure labels drop redundant bold markers`() {
        let source = """
        <details><summary>Merge Risk: <strong> Low</strong> · up to 999b0</summary>Finding.</details>
        <details><summary><strong> Recent review info</strong></summary>Metadata.</details>
        <details><summary>** Recent review info**</summary>Metadata.</details>
        """
        let summaries = MarkdownText.parsedChunks(source).compactMap(\.detailsSummary)
        #expect(summaries == ["Merge Risk:  Low · up to 999b0", "Recent review info", "Recent review info"])
        #expect(MarkdownText.strippingHTML("<strong>Keep body bold</strong>") == "**Keep body bold**")
    }

    @Test
    func `disclosure labels preserve literal asterisks in code`() {
        let source = "<details><summary><strong>Files</strong>: <code>**/*.swift</code> and `**/*.md`</summary>"
            + "Finding.</details>"
        #expect(MarkdownText.parsedChunks(source).first?.detailsSummary == "Files: `**/*.swift` and `**/*.md`")
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
    func `quoted review paragraphs stay separate`() {
        let source = "<blockquote><p>First finding.</p><p>Second finding.</p></blockquote>"
        let content = MarkdownText.content(source)
        #expect(String(content.characters) == "First finding.Second finding.")
        #expect(MarkdownTestSupport.kinds(content).count { $0 == .paragraph } == 2)
        #expect(MarkdownTestSupport.kinds(content).contains(.blockQuote))
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
        let content = MarkdownText.content(source)
        #expect(String(content.characters).contains("☑ Review"))
        #expect(MarkdownTestSupport.kinds(content).contains(.tableHeaderRow))
        #expect(MarkdownTestSupport.kinds(content).contains(.blockQuote))
        #expect(content.runs.contains { $0.link?.absoluteString == "https://example.com" })
    }
}
