import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A read-only conversation log for a past session, themed like the
/// terminals: black on white in light mode, white on black in dark.
/// Assistant prose renders as Markdown and fenced code blocks are
/// syntax highlighted.
public struct TranscriptLogView: View {
    // MARK: Lifecycle

    /// Creates a log view over parsed transcript entries.
    public init(entries: [TranscriptEntry]) {
        self.entries = entries
    }

    // MARK: Public

    /// The scrolling log.
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(entries) { entry in
                    row(entry)
                }
                if entries.isEmpty {
                    Text("Empty transcript.").foregroundStyle(.secondary)
                }
            }
            .padding(Self.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Conversations read newest-last, so open at the end.
        .defaultScrollAnchor(.bottom)
        .font(.callout)
        .foregroundStyle(colorScheme == .dark ? Color.white : .black)
        .background(colorScheme == .dark ? Color.black : .white)
    }

    // MARK: Private

    /// One piece of an entry: prose or a fenced code block.
    private struct Segment: Identifiable {
        let id: Int
        let code: Bool
        let language: SyntaxLanguage?
        let text: String
    }

    private static let spacing: CGFloat = 8
    private static let segmentSpacing: CGFloat = 4
    private static let codePadding: CGFloat = 6
    private static let codeBackgroundOpacity = 0.06
    private static let fenceLength = 3

    @Environment(\.colorScheme)
    private var colorScheme

    private let entries: [TranscriptEntry]

    @ViewBuilder
    private func row(_ entry: TranscriptEntry) -> some View {
        switch entry.role {
        case .user:
            (Text("❯ ").bold().foregroundStyle(.blue) + Text(entry.text).bold())
                .font(.callout.monospaced())
                .textSelection(.enabled)

        case .assistant:
            VStack(alignment: .leading, spacing: Self.segmentSpacing) {
                ForEach(Self.segments(of: entry.text)) { segment in
                    if segment.code {
                        codeBlock(segment)
                    } else {
                        Text(Self.markdown(segment.text)).textSelection(.enabled)
                    }
                }
            }

        case .tool:
            Text("⚙ " + entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func codeBlock(_ segment: Segment) -> some View {
        let lines = segment.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HighlightedLine(line: line, language: segment.language)
            }
        }
        .font(.callout.monospaced())
        .padding(Self.codePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(Self.codeBackgroundOpacity))
        .textSelection(.enabled)
    }

    /// Splits text on ``` fences into prose and code segments.
    private static func segments(of text: String) -> [Segment] {
        var segments = [Segment]()
        var buffer = [String]()
        var inCode = false
        var language: SyntaxLanguage?

        func flush() {
            let joined = buffer.joined(separator: "\n")
            if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                segments.append(Segment(id: segments.count, code: inCode, language: language, text: joined))
            }
            buffer = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") {
                flush()
                inCode.toggle()
                language = inCode ? fenceLanguage(String(line.dropFirst(fenceLength))) : nil
            } else {
                buffer.append(String(line))
            }
        }
        flush()
        return segments
    }

    private static func fenceLanguage(_ tag: String) -> SyntaxLanguage? {
        switch tag.trimmingCharacters(in: .whitespaces) {
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

        default:
            nil
        }
    }

    /// Inline markdown, falling back to the raw text when parsing
    /// fails.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
            ),
        )) ?? AttributedString(text)
    }
}
