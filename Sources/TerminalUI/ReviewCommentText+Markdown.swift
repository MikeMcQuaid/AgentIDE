import Foundation
import Markdown
import SwiftSoup

extension ReviewCommentText {
    private static let billingNotice = "This review was completed with usage-based billing:"
    private static let thankYou = "Thanks for using CodeRabbit!"

    static func protectedMarkdown(_ text: String, isCodeRabbit: Bool) throws -> MarkdownHTMLCode {
        try MarkdownHTMLCode(text) { node in
            if isCodeRabbit, node is BlockQuote, let paragraph = node.child(at: 0) as? Paragraph,
               paragraph.plainText.contains(billingNotice)
            {
                return ""
            }
            if isCodeRabbit, let paragraph = node as? Paragraph, paragraph.plainText.hasPrefix(thankYou),
               paragraph.children.contains(where: { $0 is InlineCode }) == false
            {
                return ""
            }
            return nil
        }
    }

    static func withoutNotices(_ source: String) -> String {
        do {
            let document = try SwiftSoup.parseBodyFragment(source)
            // Pretty printing would serialise entities instead of reusing source ranges.
            document.outputSettings().prettyPrint(pretty: false)
            var result = source
            for element in try document.select("details, blockquote, p, sub, sup") {
                let summary = try element.select("summary").first()?.text() ?? ""
                let receipt = summary.hasSuffix("Usage-based review receipt") || summary == "❤️ Share"
                let notice = try element.tagName() == "blockquote" && element.select("pre, code").isEmpty()
                    && element.text().contains(billingNotice)
                let promotion = try ["p", "sub", "sup"].contains(element.tagName())
                    && element.select("pre, code").isEmpty() && element.text().hasPrefix(thankYou)
                if receipt || notice || promotion,
                   let range = try result.range(of: element.outerHtml(), options: .literal)
                {
                    result.removeSubrange(range)
                }
            }
            return result
        } catch {
            return source
        }
    }
}
