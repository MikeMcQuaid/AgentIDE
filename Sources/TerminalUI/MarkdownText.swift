import AgentIDEDomain
import SwiftUI

/// Renders markdown with fenced code blocks: inline syntax through
/// AttributedString, code fences as monospaced blocks. SwiftUI's
/// Text alone leaves fences as literal backticks, which made review
/// comments look unrendered.
public struct MarkdownText: View {
    // MARK: Lifecycle

    /// Creates the view for one markdown string.
    public init(_ text: String) {
        self.text = text
    }

    // MARK: Public

    /// The stacked prose and code segments.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isCode {
                    code(segment.text, language: segment.language)
                } else {
                    prose(segment.text)
                }
            }
        }
    }

    // MARK: Private

    private struct Segment {
        let text: String
        let isCode: Bool
        var language: SyntaxLanguage?
    }

    private static let spacing: CGFloat = 4
    private static let codePadding: CGFloat = 6
    private static let codeCornerRadius: CGFloat = 5
    private static let codeBackgroundOpacity = 0.5

    private let text: String

    /// The text split on ``` fences after stripping the HTML wrapper
    /// tags review bots emit; each fence's language tag drives the
    /// block's highlighting.
    private var segments: [Segment] {
        var results = [Segment]()
        var current = [Substring]()
        var inCode = false
        var language: SyntaxLanguage?
        for line in Self.strippingHTML(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let joined = current.joined(separator: "\n")
                if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    results.append(Segment(text: joined, isCode: inCode, language: language))
                }
                current = []
                language = inCode ? nil : Self.syntaxLanguage(for: String(trimmed.dropFirst("```".count)))
                inCode.toggle()
            } else {
                current.append(line)
            }
        }
        let joined = current.joined(separator: "\n")
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            results.append(Segment(text: joined, isCode: inCode, language: language))
        }
        return results
    }

    /// A fenced block: monospaced, syntax highlighted when the fence
    /// named a known language.
    private func code(_ text: String, language: SyntaxLanguage?) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HighlightedLine.text(line: line.isEmpty ? " " : line, language: language)
                    .font(CodeStyle.font)
            }
        }
        .textSelection(.enabled)
        .padding(Self.codePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.codeCornerRadius)
                .fill(.quaternary.opacity(Self.codeBackgroundOpacity)),
        )
    }

    /// Prose renders headings as bold lines, since the inline parser
    /// would keep their `#` markers literal, and everything else as
    /// inline markdown.
    @ViewBuilder
    private func prose(_ text: String) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                Text(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            } else if trimmed.isEmpty == false {
                Text(Self.inline(String(line)))
                    .textSelection(.enabled)
            }
        }
    }

    /// The fence tag's language, tolerating common aliases.
    private static func syntaxLanguage(for tag: String) -> SyntaxLanguage? {
        switch tag.trimmingCharacters(in: .whitespaces).lowercased() {
        case "swift":
            .swift

        case "rb",
             "ruby":
            .ruby

        case "bash",
             "sh",
             "shell",
             "zsh":
            .shell

        case "yaml",
             "yml":
            .yaml

        case "markdown",
             "md":
            .markdown

        default:
            nil
        }
    }

    /// Drops HTML comments and unwraps the details and summary tags
    /// bots fold their reports into.
    private static func strippingHTML(_ text: String) -> String {
        var stripped = text.replacing(/<!--[\s\S]*?-->/, with: "")
        for tag in ["<details>", "</details>", "<summary>", "</summary>"] {
            stripped = stripped.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        return stripped
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
