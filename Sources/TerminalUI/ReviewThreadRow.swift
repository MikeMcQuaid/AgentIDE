import AgentIDEDomain
import AppKit
import SwiftUI

/// One GitHub conversation or local finding: a header with the
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
        localReviewer: AgentKind? = nil,
        onMakeFix: (@MainActor () async -> Void)? = nil,
        onToggleResolved: (@MainActor () async -> Void)? = nil,
        allowsActions: Bool = true,
        allowsFix: Bool = true,
    ) {
        self.thread = thread
        self.onEdit = onEdit
        self.localReviewer = localReviewer
        self.onMakeFix = onMakeFix
        self.allowsActions = allowsActions
        self.allowsFix = allowsFix
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
                HStack {
                    Spacer()
                    resolveButton
                    if let onMakeFix, thread.isResolved == false {
                        BusyButton(
                            "Make fix",
                            busy: "Preparing",
                            prominent: true,
                            disabled: allowsFix == false,
                            action: onMakeFix,
                        )
                        .controlSize(.small)
                        .hoverHelp("Prepare an editable fix prompt for this finding to copy into the main agent pane")
                    }
                }
                .disabled(allowsActions == false)
            }
        }
        .padding(Self.padding)
        .background(.quaternary.opacity(Self.backgroundOpacity), in: RoundedRectangle(cornerRadius: Self.corner))
        .overlay {
            if localReviewer != nil {
                RoundedRectangle(cornerRadius: Self.corner)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .opacity(thread.isResolved ? Self.resolvedOpacity : 1)
        .onChange(of: thread.isResolved) { expandOverrides = [] }
        .animation(Motion.quick, value: thread.isResolved)
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
    private static let corner: CGFloat = 6
    private static let backgroundOpacity = 0.5
    private static let resolvedOpacity = 0.6
    private static let iconSize: CGFloat = 16

    /// Overrides per row once toggled; resolved conversations
    /// otherwise start minimised.
    @State private var expandOverrides: [Bool] = []

    private let thread: ReviewThread
    private let onEdit: (@MainActor () -> Void)?
    private let localReviewer: AgentKind?
    private let onMakeFix: (@MainActor () async -> Void)?
    private let allowsActions: Bool
    private let allowsFix: Bool
    private let onToggleResolved: (@MainActor () async -> Void)?

    private var isExpanded: Bool {
        expandOverrides.last ?? (thread.isResolved == false)
    }

    private var anchor: String {
        thread.path + (thread.line.map { ":" + String($0) } ?? "")
    }

    /// The comments; the header names the first author, so a name
    /// only appears in the body where a different author replies.
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
            if let localReviewer {
                Image(localReviewer.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityLabel(localReviewer.displayName + " local review")
            } else {
                Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                    .foregroundStyle(thread.isResolved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(thread.isResolved ? "Resolved GitHub conversation" : "Open GitHub conversation")
            }
        }
        .buttonStyle(.borderless)
        .hoverHelp("Collapse or expand this conversation")
    }

    @ViewBuilder private var resolveButton: some View {
        // A REST-fallback thread carries no id to resolve.
        if thread.resolveID.isEmpty == false || localReviewer != nil, let onToggleResolved {
            BusyButton(
                localReviewer == nil
                    ? (thread.isResolved ? "Unresolve" : "Resolve")
                    : (thread.isResolved ? "Reopen comment" : "Resolve comment"),
                busy: thread.isResolved ? "Unresolving" : "Resolving",
                action: onToggleResolved,
            )
            .controlSize(.small)
            .hoverHelp(
                localReviewer == nil
                    ? (thread.isResolved ? "Reopen on GitHub" : "Resolve on GitHub")
                    : (thread.isResolved ? "Reopen this local finding" : "Resolve locally without changing code"),
            )
        }
    }

    /// Icon, bold author, anchor, then the edit jump on the right.
    private var header: some View {
        HStack(spacing: Self.spacing) {
            collapseToggle
            Text(thread.comments.first?.author ?? "")
                .interfaceFont(.callout, weight: .semibold)
                .textSelection(.enabled)
            Text(localReviewer == nil ? "GitHub" : (thread.isResolved ? "Resolved locally" : "Local review"))
                .interfaceFont(.caption)
                .foregroundStyle(localReviewer == nil ? Color.secondary : Color.accentColor)
            Text(anchor)
                .interfaceFont(.callout, monospaced: true)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(thread.asText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .accessibilityLabel("Copy this conversation")
            }
            .buttonStyle(.borderless)
            .hoverHelp("Copy this conversation, with its file and line, to the clipboard")
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .accessibilityLabel("Edit " + anchor)
                }
                .buttonStyle(.borderless)
                .hoverHelp("Open this file at the anchored line in the built-in editor")
            }
        }
    }
}
