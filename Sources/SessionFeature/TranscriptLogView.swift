import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A read-only conversation log for a past session, themed like the
/// terminals: black on white in light mode, white on black in dark.
/// Assistant prose renders as Markdown and fenced code blocks are
/// syntax highlighted.
struct TranscriptLogView: View {
    // MARK: Lifecycle

    /// Creates a log view over parsed transcript entries.
    init(entries: [TranscriptEntry]) {
        self.entries = entries
    }

    // MARK: Internal

    /// The scrolling log.
    var body: some View {
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
        // The semantic text colours: they track appearance and the
        // Increase Contrast setting, where literal black and white
        // tracked nothing.
        .foregroundStyle(Color(nsColor: .textColor))
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private let entries: [TranscriptEntry]

    @ViewBuilder
    private func row(_ entry: TranscriptEntry) -> some View {
        switch entry.role {
        case .user:
            Text("\(Text("❯ ").bold().foregroundStyle(.blue))\(Text(entry.text).bold())")
                .font(.callout.monospaced())
                .textSelection(.enabled)

        case .assistant:
            // The shared renderer, so agent output, review comments
            // and pull request bodies all read the same.
            MarkdownText(entry.text)

        case .tool:
            Text("⚙ " + entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}
