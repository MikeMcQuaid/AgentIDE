import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownAlertTests {
    @Test(arguments: ["Note", "Tip", "Important", "Warning", "Caution"])
    func `all GitHub alerts keep body formatting`(title: String) {
        let content = MarkdownText.content(
            "> [!" + title.uppercased() + "]\n> **Check** `file.swift`.\n>\n> 3. Third\n> 4. Fourth",
        )
        #expect(String(content.characters).hasPrefix(title + "\n"))
        #expect(MarkdownTestSupport.kinds(content).contains(.blockQuote))
        #expect(MarkdownTestSupport.kinds(content).contains(.listItem(ordinal: 3)))
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test(arguments: ["[!UNKNOWN]", "`[!NOTE]`", "Ordinary quote"])
    func `ordinary quotes and code markers stay literal`(source: String) {
        let content = MarkdownText.content("> " + source)
        #expect(String(content.characters) == source.replacing("`", with: ""))
    }

    @Test(arguments: ["> - First\n>\n> [!NOTE] Literal", "- First\n\n  [x] Literal", "- `[x]` Literal"])
    func `markers outside the opening text stay literal`(source: String) {
        let content = String(MarkdownText.content(source).characters)
        #expect(content.contains(source.contains("[!NOTE]") ? "[!NOTE]" : "[x]"))
    }

    @Test
    func `alert and task examples inside code remain literal`() {
        let source = "> [!NOTE]\n- [x] Literal\n"
        let content = MarkdownText.content("```markdown\n" + source + "``` ")
        #expect(String(content.characters) == source)
        #expect(MarkdownTestSupport.kinds(content).contains(.codeBlock(languageHint: "markdown")))
    }
}
