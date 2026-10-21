import SwiftUI
import Textual

private let parseCacheCap = 512

// MARK: - MarkdownText

/// The shared native GFM renderer, with GitHub's layout and the app's fonts.
public struct MarkdownText: View {
    // MARK: Lifecycle

    /// Relative images resolve beside the Markdown file when it has a directory.
    public init(_ text: String, relativeTo directory: String? = nil) {
        self.text = text
        self.directory = directory
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                if let summary = chunk.detailsSummary {
                    DisclosureGroup(
                        content: { Self(chunk.text, relativeTo: directory) },
                        label: { markdown(summary).fontWeight(.medium) },
                    )
                } else {
                    markdown(chunk.text)
                }
            }
        }
        .interfaceFont(.callout)
        .foregroundStyle(Color(nsColor: .textColor))
        .textual
        .inlineStyle(.gitHub
            .code(.font(codeStyle.font), .backgroundColor(DynamicColor(Color(nsColor: .quaternaryLabelColor))))
            .link(.foregroundColor(DynamicColor(Color(nsColor: .linkColor)))))
        .textual
        .codeBlockStyle(MarkdownCodeStyle())
        .textual
        .orderedListMarker(StructuredText.MapOrdinalListMarker { String($0) })
        .textual
        .highlighterTheme(MarkdownCodeStyle.highlighterTheme)
        .textual
        .imageAttachmentLoader(.image(
            relativeTo: directory.map { URL(filePath: $0, directoryHint: .isDirectory) },
        ))
        .textual
        .textSelection(.enabled)
        .textual
        .structuredTextStyle(.gitHub)
    }

    // MARK: Internal

    struct Chunk {
        let text: String
        let detailsSummary: String?
    }

    /// Content caches are shared by previews, conversations and review comments.
    final class ParseCache<Value> {
        // MARK: Lifecycle

        init() {
            // Starts empty.
        }

        deinit {
            // The caches live for the process.
        }

        // MARK: Internal

        func value(for key: String, make: (String) -> Value) -> Value {
            if let cached = store[key] {
                return cached
            }
            let value = make(key)
            if store.count >= parseCacheCap {
                store = [:]
            }
            store[key] = value
            return value
        }

        // MARK: Private

        private var store: [String: Value] = [:]
    }

    static let chunkCache: ParseCache<[Chunk]> = .init()
    static let contentCache: ParseCache<AttributedString> = .init()
    static let spacing: CGFloat = 16

    static func parsedChunks(_ text: String) -> [Chunk] {
        (try? MarkdownHTML(text).chunks) ?? [Chunk(text: text, detailsSummary: nil)]
    }

    // MARK: Private

    private struct Parser: MarkupParser {
        func attributedString(for input: String) -> AttributedString {
            MarkdownText.content(input)
        }
    }

    private var codeStyle: CodeStyle = .init()
    private let text: String
    private let directory: String?

    private var chunks: [Chunk] {
        Self.chunkCache.value(for: text) { Self.parsedChunks($0) }
    }

    private func markdown(_ source: String) -> some View {
        StructuredText(source, parser: Parser())
            // Textual retains resolved attachments when new content has no images.
            .id(source)
            .id(directory)
    }
}
