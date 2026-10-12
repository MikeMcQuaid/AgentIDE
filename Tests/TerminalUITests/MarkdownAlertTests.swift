@testable import TerminalUI
import Testing

@MainActor
struct MarkdownAlertTests {
    @Test(arguments: ["Note", "Tip", "Important", "Warning", "Caution"])
    func `all GitHub alerts keep body formatting`(title: String) throws {
        let block = try #require(MarkdownText.proseBlocks(
            "> [!" + title.uppercased() + "]\n> **Check** `file.swift`.\n>\n> - First\n> - Second",
        )
        .first)
        guard case let .quote(text) = block else {
            Issue.record("The alert should remain a callout")
            return
        }

        #expect(text.hasPrefix("**" + title + "**\n\n"))
        #expect(text.contains("**Check** `file.swift`."))
        #expect(text.contains("- First\n- Second"))
    }

    @Test(arguments: ["> [!UNKNOWN]\n> Literal", "> `[!NOTE]`\n> Literal", "> Ordinary quote"])
    func `ordinary quotes and code markers stay literal`(source: String) throws {
        let block = try #require(MarkdownText.proseBlocks(source).first)
        guard case let .quote(text) = block else {
            Issue.record("The quote should remain a quote")
            return
        }

        #expect(text.hasPrefix("**") == false)
    }

    @Test
    func `alert examples inside code remain literal`() throws {
        let source = "> [!NOTE]\n> Literal"
        let block = try #require(MarkdownText.proseBlocks("```markdown\n" + source + "\n```").first)
        guard case let .code(text, _) = block else {
            Issue.record("The example should remain code")
            return
        }

        #expect(text == source)
    }

    @Test
    func `a CodeRabbit processing note renders without literal markers`() throws {
        let body = "Currently processing new changes in this PR. This may take a few minutes, please wait…"
        let blocks = MarkdownText.proseBlocks(MarkdownText.strippingHTML(
            "> [!NOTE]\n> " + body,
        ))
        let block = try #require(blocks.first)
        guard case let .quote(text) = block else {
            Issue.record("The note should remain a callout")
            return
        }

        #expect(text.contains("[!NOTE]") == false)
        #expect(text.contains("**Note**"))
        #expect(text.contains(body))
    }
}
