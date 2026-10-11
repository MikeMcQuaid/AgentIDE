import Foundation
import Markdown

/// Protect code and Markdown links before an HTML parser sees their brackets.
struct MarkdownHTMLCode {
    // MARK: Lifecycle

    init(_ text: String) throws {
        let lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        func sourceIndex(at location: SourceLocation) -> String.Index? {
            guard location.line > 0, location.line <= lines.count, location.column > 0 else {
                return nil
            }

            let line = lines[location.line - 1].utf8
            guard let index = line.index(
                line.startIndex, offsetBy: location.column - 1, limitedBy: line.endIndex,
            ) else {
                return nil
            }

            return String.Index(index, within: text)
        }
        var ranges = [Range<String.Index>]()
        func visit(_ node: any Markup) throws {
            if node is CodeBlock || node is InlineCode || node is Link || node is Markdown.Image,
               let range = node.range
            {
                guard let start = sourceIndex(at: range.lowerBound), let end = sourceIndex(at: range.upperBound),
                      start <= end, (ranges.last?.upperBound ?? text.startIndex) <= start
                else {
                    throw InvalidSourceRange()
                }

                ranges.append(start ..< end)
            } else {
                for child in node.children {
                    try visit(child)
                }
            }
        }
        try visit(Document(parsing: text))
        var escaped = text
        var saved = [(String, String)]()
        let prefix = "AGENTIDE" + UUID().uuidString
        for (index, range) in ranges.reversed().enumerated() {
            let key = prefix + String(index) + "END"
            saved.append((key, String(text[range])))
            escaped.replaceSubrange(range, with: key)
        }
        source = escaped
        replacements = saved
    }

    // MARK: Internal

    let source: String

    func restore(_ text: String) -> String {
        replacements.reduce(text) { $0.replacing($1.0, with: $1.1) }
    }

    // MARK: Private

    private struct InvalidSourceRange: Error {}

    private let replacements: [(String, String)]
}
