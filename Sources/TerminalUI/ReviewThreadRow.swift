import AgentIDEDomain
import SwiftUI

/// One pull request conversation: a single header line with the
/// anchor, edit jump, author and resolve toggle over the comments;
/// resolved conversations start minimised to their header.
public struct ReviewThreadRow: View {
    // MARK: Lifecycle

    /// Creates the row; `onEdit` opens the anchored file when the
    /// surface can.
    @preconcurrency
    public init(
        thread: ReviewThread,
        onEdit: (@MainActor () -> Void)? = nil,
        onToggleResolved: @escaping @MainActor () async -> Void,
    ) {
        self.thread = thread
        self.onEdit = onEdit
        self.onToggleResolved = onToggleResolved
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            if isExpanded {
                // Every comment in one markdown block: separate
                // views cannot share a selection, so one block lets
                // a drag span all of them.
                MarkdownText(markdown)
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

    /// Overrides per row once toggled; resolved conversations
    /// otherwise start minimised.
    @State private var expandOverrides: [Bool] = []

    private let thread: ReviewThread
    private let onEdit: (@MainActor () -> Void)?
    private let onToggleResolved: @MainActor () async -> Void

    private var isExpanded: Bool {
        expandOverrides.last ?? (thread.isResolved == false)
    }

    private var anchor: String {
        thread.path + (thread.line.map { ":" + String($0) } ?? "")
    }

    /// The comments; the header line already names the first
    /// author, so only a mid-thread author change repeats a name.
    private var markdown: String {
        var sections = [String]()
        var lastAuthor = thread.comments.first?.author ?? ""
        for comment in thread.comments {
            if comment.author != lastAuthor {
                sections.append("**" + comment.author + "**")
                lastAuthor = comment.author
            }
            sections.append(comment.body)
        }
        return sections.joined(separator: "\n\n")
    }

    private var collapseToggle: some View {
        Button {
            expandOverrides = [isExpanded == false]
        } label: {
            Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                .foregroundStyle(thread.isResolved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityLabel(thread.isResolved ? "Resolved conversation" : "Open conversation")
        }
        .buttonStyle(.borderless)
        .hoverHelp("Collapse or expand this conversation")
    }

    @ViewBuilder private var resolveButton: some View {
        // A REST-fallback thread carries no id to resolve.
        if thread.resolveID.isEmpty == false {
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
    }

    /// Icon, anchor, edit, author and the resolve toggle in one line.
    private var header: some View {
        HStack(spacing: Self.spacing) {
            collapseToggle
            Text(anchor)
                .font(.callout.monospaced())
                .lineLimit(1)
                .textSelection(.enabled)
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .accessibilityLabel("Edit " + anchor)
                }
                .buttonStyle(.borderless)
                .hoverHelp("Open this file at the anchored line in the built-in editor")
            }
            Text(thread.comments.first?.author ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            resolveButton
        }
    }
}
