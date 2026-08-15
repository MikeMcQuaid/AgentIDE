import AgentIDEDomain
import SwiftUI

/// One pull request conversation with its resolve state toggleable;
/// shown inline in the review under the file it anchors to and on
/// the pull request conversation page.
public struct ReviewThreadRow: View {
    // MARK: Lifecycle

    /// Creates the row.
    @preconcurrency
    public init(thread: ReviewThread, onToggleResolved: @escaping @MainActor () async -> Void) {
        self.thread = thread
        self.onToggleResolved = onToggleResolved
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                    .foregroundStyle(thread.isResolved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(thread.isResolved ? "Resolved conversation" : "Open conversation")
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
            // The anchor and every comment in one markdown block:
            // separate views cannot share a selection, so one block
            // lets a drag span the file, line and all the comments.
            MarkdownText(markdown)
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

    private let thread: ReviewThread
    private let onToggleResolved: @MainActor () async -> Void

    /// The `path:line` anchor, then the comments, each under its
    /// author; a run of comments by one author names them once.
    private var markdown: String {
        let anchor = "`" + thread.path + (thread.line.map { ":" + String($0) } ?? "") + "`"
        var sections = [anchor]
        var lastAuthor = ""
        for comment in thread.comments {
            if comment.author != lastAuthor {
                sections.append("**" + comment.author + "**")
                lastAuthor = comment.author
            }
            sections.append(comment.body)
        }
        return sections.joined(separator: "\n\n")
    }
}
