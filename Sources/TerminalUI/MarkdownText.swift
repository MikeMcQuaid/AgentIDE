import AgentIDEDomain
import SwiftUI
import Synchronization

/// The most entries a parse cache holds before being wiped; at file
/// scope because a generic type cannot hold a static stored value.
private let parseCacheCap = 512

// MARK: - MarkdownText

/// Renders markdown with fenced code blocks: inline syntax through
/// AttributedString, code fences as monospaced blocks. SwiftUI's
/// Text alone leaves fences as literal backticks, which made review
/// comments look unrendered.
public struct MarkdownText: View {
    // MARK: Lifecycle

    /// Creates the view for one markdown string. `relativeTo` is the
    /// directory its own file sits in, where it has one: a README's
    /// `![shot](docs/screenshot.png)` means a file beside it, and
    /// without somewhere to be relative to it can only be alt text.
    public init(_ text: String, relativeTo directory: String? = nil) {
        self.text = text
        self.directory = directory
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

    // MARK: Internal

    /// A top-level run of markdown, either plain or one details
    /// block folded behind its summary; internal so the caches can
    /// name it.
    struct Chunk {
        let text: String
        let detailsSummary: String?
    }

    /// A parse memoised by its input, since every parse here is
    /// pure and the views re-evaluate per render: a conversation of
    /// forty comments re-parsed all forty on every state change.
    /// Wiped wholesale when full rather than ordered for eviction.
    final class ParseCache<Value: Sendable>: Sendable {
        // MARK: Lifecycle

        init() {
            // Starts empty.
        }

        deinit {
            // The caches live for the process.
        }

        // MARK: Internal

        func value(for key: String, make: (String) -> Value) -> Value {
            if let cached = store.withLock({ $0[key] }) {
                return cached
            }

            let value = make(key)
            store.withLock { values in
                if values.count >= parseCacheCap {
                    values = [:]
                }
                values[key] = value
            }
            return value
        }

        // MARK: Private

        private let store: Mutex<[String: Value]> = .init([:])
    }

    static let chunkCache: ParseCache<[Chunk]> = .init()
    static let blockCache: ParseCache<[ProseBlock]> = .init()
    static let inlineCache: ParseCache<AttributedString> = .init()

    /// Where an image's source points: a web address as written, and
    /// a path on this Mac as a file. A relative path has nothing to
    /// be relative to here, so it stays alt text rather than
    /// guessing at a directory.
    static func imageURL(_ source: String, relativeTo directory: String? = nil) -> URL? {
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return URL(string: source)
        }
        if source.hasPrefix("/") {
            return URL(filePath: source)
        }

        return directory.map { URL(filePath: $0 + "/" + source) }
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let tableSpacing: CGFloat = 12
    private static let codePadding: CGFloat = 6
    private static let codeCornerRadius: CGFloat = 5
    private static let codeBackgroundOpacity = 0.5

    private let text: String

    /// See `init(_:relativeTo:)`: where a relative image source
    /// points from.
    private let directory: String?

    /// The text split on `<details>` blocks, which render collapsed;
    /// bots fold their long reports into them for a reason.
    private var chunks: [Chunk] {
        Self.chunkCache.value(for: text) { Self.parsedChunks($0) }
    }

    /// One chunk's blocks, parsed by the official GitHub-flavoured
    /// parser after the HTML mapping, from the cache when unchanged.
    private func segmentViews(_ text: String) -> some View {
        let blocks = Self.blockCache.value(for: text) { Self.proseBlocks(Self.strippingHTML($0)) }
        return ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case let .heading(title):
                Text(Self.inline(title)).fontWeight(.semibold).textSelection(.enabled)

            case .rule:
                Divider()

            case let .code(text, language):
                code(text, language: language)

            case let .table(header, rows):
                table(header: header, rows: rows)

            case let .image(source, alt):
                image(source: source, alt: alt)

            case let .text(line):
                Text(Self.inline(line)).textSelection(.enabled)
            }
        }
    }

    /// An image the markdown embeds, drawn at its own size up to
    /// the width it is given and never blown up past it. Anything
    /// that will not load stays as its alt text, which is what the
    /// text said before images were drawn at all.
    @ViewBuilder
    private func image(source: String, alt: String) -> some View {
        if let url = Self.imageURL(source, relativeTo: directory) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(Self.inline(alt)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(alt)
        } else {
            Text(Self.inline(alt)).foregroundStyle(.secondary)
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

    private static func parsedChunks(_ text: String) -> [Chunk] {
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
}
