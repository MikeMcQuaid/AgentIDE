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

    /// The stacked prose and code segments, with details blocks
    /// collapsed behind their summaries. One font for every markdown
    /// surface in the app.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                if let summary = chunk.detailsSummary {
                    DisclosureGroup(
                        content: { Self(chunk.text) },
                        label: { Text(Self.inline(summary)).fontWeight(.medium) },
                    )
                } else {
                    segmentViews(chunk.text)
                }
            }
        }
        .font(.callout)
    }

    // MARK: Private

    /// A top-level run of markdown, either plain or one details
    /// block folded behind its summary.
    private struct Chunk {
        let text: String
        let detailsSummary: String?
    }

    private static let spacing: CGFloat = 4
    private static let tableSpacing: CGFloat = 12
    private static let codePadding: CGFloat = 6
    private static let codeCornerRadius: CGFloat = 5
    private static let codeBackgroundOpacity = 0.5

    private let text: String

    /// The text split on `<details>` blocks, which render collapsed;
    /// bots fold their long reports into them for a reason.
    private var chunks: [Chunk] {
        var results = [Chunk]()
        var remainder = Substring(text)
        while let match = remainder.firstMatch(of: /<details[^>]*>([\s\S]*?)<\/details>/.ignoresCase()) {
            let before = String(remainder[..<match.range.lowerBound])
            if before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                results.append(Chunk(text: before, detailsSummary: nil))
            }
            var inner = String(match.output.1)
            var summary = ""
            if let heading = inner.firstMatch(of: /<summary>([\s\S]*?)<\/summary>/.ignoresCase()) {
                summary = String(heading.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
                inner.removeSubrange(heading.range)
            }
            results.append(Chunk(text: inner, detailsSummary: summary.isEmpty ? "Details" : summary))
            remainder = remainder[match.range.upperBound...]
        }
        if remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            results.append(Chunk(text: String(remainder), detailsSummary: nil))
        }
        return results
    }

    /// One chunk's fences and prose.
    private func segmentViews(_ text: String) -> some View {
        ForEach(Array(segments(of: text).enumerated()), id: \.offset) { _, segment in
            if segment.isCode {
                code(segment.text, language: segment.language)
            } else {
                prose(segment.text)
            }
        }
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

    /// Wide tables scroll within the pane instead of demanding
    /// their full width and squeezing the panes around them.
    private func table(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { tableGrid(header: header, rows: rows) }
    }

    private func tableGrid(header: [String], rows: [[String]]) -> some View {
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

    /// The text split on ``` fences after stripping the HTML wrapper
    /// tags review bots emit; each fence's language tag drives the
    /// block's highlighting.
    private func segments(of text: String) -> [Segment] {
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
}
