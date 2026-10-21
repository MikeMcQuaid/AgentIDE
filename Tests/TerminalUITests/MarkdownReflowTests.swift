import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownReflowTests {
    @Test
    func `soft breaks stay within their paragraph`() {
        let content = MarkdownText.content("First line\nsecond line\n\nNext paragraph")
        #expect(String(content.characters).hasPrefix("First line second line"))
        #expect(MarkdownTestSupport.kinds(content).count { $0 == .paragraph } == 2)
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.softBreak) == true })
    }

    @Test(arguments: ["  ", "\\"])
    func `explicit hard breaks remain hard`(marker: String) {
        let content = MarkdownText.content("First" + marker + "\nSecond")
        #expect(String(content.characters) == "First\nSecond")
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.lineBreak) == true })
    }

    @Test
    func `code keeps indentation newlines and literal markup`() {
        let source = "if ready {\n    print(\"<strong>literal</strong>\")\n}\n"
        let content = MarkdownText.content("```swift\n" + source + "```")
        #expect(String(content.characters) == source)
        #expect(MarkdownTestSupport.kinds(content).contains(.codeBlock(languageHint: "swift")))
    }

    @Test(arguments: ["https://example.com/image.png", "docs/image.png", "/Users/Shared/image.png"])
    func `images preserve their source and alt text`(source: String) {
        let content = MarkdownText.content("![A diagram](" + source + ")")
        #expect(String(content.characters) == "A diagram")
        #expect(content.runs.contains { $0.imageURL?.path == URL(string: source)?.path })
        if source.hasPrefix("/") {
            #expect(content.runs.contains { $0.imageURL?.isFileURL == true })
        }
    }
}
