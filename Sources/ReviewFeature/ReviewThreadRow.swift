import AgentIDEDomain
import SwiftUI
import TerminalUI

/// One pull request conversation shown inline in the review, under
/// the file it anchors to, with its resolve state toggleable.
struct ReviewThreadRow: View {
    // MARK: Internal

    let thread: ReviewThread
    let onToggleResolved: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                    .foregroundStyle(thread.isResolved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(thread.isResolved ? "Resolved conversation" : "Open conversation")
                if let line = thread.line {
                    Text("line " + String(line))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BusyButton(
                    thread.isResolved ? "Unresolve" : "Resolve",
                    busy: "Saving",
                    action: onToggleResolved,
                )
                .controlSize(.small)
                .hoverHelp(
                    thread.isResolved
                        ? "Reopen this conversation on GitHub"
                        : "Mark this conversation resolved on GitHub",
                )
            }
            ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MarkdownText(comment.body)
                }
            }
        }
        .padding(Self.padding)
        .background(.quaternary.opacity(Self.backgroundOpacity), in: RoundedRectangle(cornerRadius: Self.corner))
        .opacity(thread.isResolved ? Self.resolvedOpacity : 1)
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
    private static let corner: CGFloat = 6
    private static let backgroundOpacity = 0.5
    private static let resolvedOpacity = 0.6
}
