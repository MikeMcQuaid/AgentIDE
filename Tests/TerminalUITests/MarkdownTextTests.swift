import Foundation
@testable import TerminalUI
import Testing

/// The same attributed content feeds Textual on every Markdown surface.
@MainActor
struct MarkdownTextTests {
    @Test(arguments: ["1. **First**\n2. Second", "1. **First**\n1. Second", "1) **First**\n2) Second"])
    func `ordered lists remain structured`(source: String) {
        let content = MarkdownText.content(source)
        let kinds = MarkdownTestSupport.kinds(content)
        #expect(kinds.contains(.orderedList))
        #expect(kinds.contains(.listItem(ordinal: 1)))
        #expect(kinds.contains(.listItem(ordinal: 2)))
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test
    func `nested lists retain independent starting numbers and blocks`() {
        let content = MarkdownText.content("""
        3. Third
        4. Fourth

           7. Nested seventh
           8. Nested eighth

           Another paragraph.

           > A quotation.

        ## Next section
        1. Restart
        2. Continue
        """)
        let kinds = MarkdownTestSupport.kinds(content)
        for ordinal in [3, 4, 7, 8, 1, 2] {
            #expect(kinds.contains(.listItem(ordinal: ordinal)))
        }
        #expect(kinds.count { $0 == .orderedList } == 3)
        #expect(kinds.contains(.blockQuote))
        #expect(kinds.contains(.header(level: 2)))
        #expect(String(content.characters).contains("Another paragraph."))
    }

    @Test(arguments: 1 ... 6)
    func `headings retain their levels and inline formatting`(level: Int) {
        let content = MarkdownText.content(String(repeating: "#", count: level) + " Use `git status` and **review**")
        #expect(MarkdownTestSupport.kinds(content).contains(.header(level: level)))
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test
    func `tables preserve alignment tasks preserve state and references resolve`() {
        let content = MarkdownText.content("""
        | Left | Centre | Right |
        | :--- | :---: | ---: |
        | `code` | **bold** | ~~old~~ |

        - [ ] Open
        - [x] Done

        [Documentation][docs] and <https://example.com>.

        [docs]: https://example.com/docs "Documentation"
        """)
        #expect(MarkdownTestSupport.kinds(content).contains(.table(columns: [
            .init(alignment: .left), .init(alignment: .center), .init(alignment: .right),
        ])))
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true })
        #expect(String(content.characters).contains("☐ Open"))
        #expect(String(content.characters).contains("☑ Done"))
        #expect(content.runs.contains { $0.link?.absoluteString == "https://example.com/docs" })
        #expect(content.runs.contains { $0.link?.absoluteString == "https://example.com" })
    }

    @Test
    func `front matter leads as a table followed by the document`() {
        let content = MarkdownText.content("""
        ---
        title: "Homebrew 7.0.0"
        date: 2026-09-05
        tags:
          - release
          - homebrew
        ---

        # Homebrew 7.0.0

        Today's release.
        """)
        let kinds = MarkdownTestSupport.kinds(content)
        #expect(kinds.contains(.tableHeaderRow))
        #expect(kinds.contains(.header(level: 1)))
        #expect(String(content.characters).contains("Homebrew 7.0.0"))
        #expect(String(content.characters).contains("- release - homebrew"))
        #expect(MarkdownText.frontMatter(in: "---\n\nSome prose\n\n---\n\nMore") == nil)
    }

    @Test
    func `front matter preserves empty cells and literal formatting`() {
        let content = MarkdownText.content("---\nempty:\nliteral: '*value* | other'\n---\n\nBody")
        let cells = MarkdownTestSupport.kinds(content).filter { kind in
            if case .tableCell = kind {
                true
            } else {
                false
            }
        }
        #expect(cells.count == 6)
        #expect(String(content.characters).contains("*value* | other"))
    }

    @Test
    func `unchanged content is parsed once`() {
        let cache = MarkdownText.ParseCache<Int>()
        var parses = 0
        for _ in 0 ..< 2 {
            #expect(cache.value(for: "same") { _ in parses += 1; return parses } == 1)
        }
        #expect(parses == 1)
        #expect(cache.value(for: "changed") { _ in parses += 1; return parses } == 2)
    }
}
