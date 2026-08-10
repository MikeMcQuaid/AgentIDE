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

    /// One structural piece of prose: GitHub comments mix headings,
    /// horizontal rules and pipe tables into their markdown.
    private enum ProseBlock {
        case heading(String)
        case rule
        case table(header: [String], rows: [[String]])
        case text(String)
    }

    private static let spacing: CGFloat = 4
    private static let tableSpacing: CGFloat = 12

    /// The shortest run of `-` or `*` that reads as a rule.
    private static let ruleMinimumLength = 3

    /// A table needs a header row and a separator row.
    private static let tableHeaderRows = 2
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

    /// Prose renders headings as bold lines (the inline parser keeps
    /// `#` literal), `---` rules as dividers, pipe tables as grids
    /// and everything else as inline markdown.
    private func prose(_ text: String) -> some View {
        ForEach(Array(Self.proseBlocks(text).enumerated()), id: \.offset) { _, block in
            switch block {
            case let .heading(title):
                Text(title).fontWeight(.semibold).textSelection(.enabled)

            case .rule:
                Divider()

            case let .table(header, rows):
                table(header: header, rows: rows)

            case let .text(line):
                Text(Self.inline(line)).textSelection(.enabled)
            }
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Self.tableSpacing, verticalSpacing: Self.spacing) {
            if header.isEmpty == false {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(Self.inline(cell)).fontWeight(.semibold)
                    }
                }
                Divider()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(Self.inline(cell)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private static func proseBlocks(_ text: String) -> [ProseBlock] {
        var blocks = [ProseBlock]()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("#") {
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                index += 1
            } else if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
            } else if trimmed.hasPrefix("|") {
                var rows = [[String]]()
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") else {
                        break
                    }

                    rows.append(cells(of: row))
                    index += 1
                }
                if rows.count >= Self.tableHeaderRows, isSeparatorRow(rows[1]) {
                    blocks.append(.table(header: rows[0], rows: Array(rows.dropFirst(Self.tableHeaderRows))))
                } else {
                    blocks.append(.table(header: [], rows: rows))
                }
            } else {
                blocks.append(.text(lines[index]))
                index += 1
            }
        }
        return blocks
    }

    /// Whether a line is a `---` or `***` horizontal rule.
    private static func isRule(_ trimmed: String) -> Bool {
        trimmed.count >= ruleMinimumLength
            && (Set(trimmed).isSubset(of: ["-"]) || Set(trimmed).isSubset(of: ["*"]))
    }

    /// The trimmed cells of one `| a | b |` row.
    private static func cells(of row: String) -> [String] {
        row.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Whether a row is the `|---|:--|` header separator.
    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        cells.isEmpty == false && cells.allSatisfy { cell in
            cell.isEmpty == false && cell.allSatisfy { $0 == "-" || $0 == ":" }
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

        case "py",
             "python":
            .python

        case "json":
            .json

        case "dockerfile":
            .dockerfile

        case "ts",
             "tsx",
             "typescript":
            .typescript

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

    /// Drops HTML comments, unwraps the details and summary tags
    /// bots fold their reports into, and converts anchors and line
    /// breaks to their markdown equivalents.
    private static func strippingHTML(_ text: String) -> String {
        var stripped = text.replacing(/<!--[\s\S]*?-->/, with: "")
        stripped = stripped.replacing(/<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/) { match in
            "[" + String(match.output.2) + "](" + String(match.output.1) + ")"
        }
        stripped = stripped.replacing(/<br\s*\/?>/, with: "\n")
        stripped = stripped.replacing(/<img[^>]*>/, with: "")
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
