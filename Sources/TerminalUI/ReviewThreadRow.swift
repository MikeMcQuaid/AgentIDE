import AgentIDEDomain
import AppKit
import SwiftUI

/// One GitHub conversation or local finding: a header with the
/// anchor, edit jump, author and resolve toggle over the comments;
/// resolved and pending conversations start minimised to their header.
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
        onToggleResolveOnPush: (@MainActor () async -> Void)? = nil,
        isPendingResolution: Bool = false,
        allowsActions: Bool = true,
        allowsFix: Bool = true,
        showsCodeContext: Bool = true,
    ) {
        self.thread = thread
        self.onEdit = onEdit
        self.localReviewer = localReviewer
        self.onMakeFix = onMakeFix
        self.allowsActions = allowsActions
        self.allowsFix = allowsFix
        self.onToggleResolved = onToggleResolved
        self.onToggleResolveOnPush = onToggleResolveOnPush
        self.isPendingResolution = isPendingResolution
        self.showsCodeContext = showsCodeContext
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            if isExpanded {
                if showsCodeContext, let context = thread.codeContext {
                    Text("Reviewed code").interfaceFont(.caption).foregroundStyle(.secondary)
                    MarkdownText(Self.fenced(context))
                }
                // Every comment in one markdown block: separate
                // views cannot share a selection, so one block lets
                // a drag span all of them.
                MarkdownText(markdown)
                HStack {
                    Spacer()
                    resolveOnPushButton
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
                .disabled(allowsActions == false || isUpdatingResolution)
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
        .onChange(of: thread.isResolved) { expandOverrides = [] }
        .onChange(of: isPendingResolution) { expandOverrides = [] }
        .animation(Motion.quick, value: isExpanded)
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
    private static let corner: CGFloat = 6
    private static let backgroundOpacity = 0.5
    private static let iconSize: CGFloat = 16
    private static let minimumFence = 3

    /// Overrides per row once toggled; resolved and pending conversations
    /// otherwise start minimised.
    @State private var expandOverrides: [Bool] = []
    @State private var isUpdatingResolution = false

    private let thread: ReviewThread
    private let onEdit: (@MainActor () -> Void)?
    private let localReviewer: AgentKind?
    private let onMakeFix: (@MainActor () async -> Void)?
    private let allowsActions: Bool
    private let allowsFix: Bool
    private let showsCodeContext: Bool
    private let onToggleResolveOnPush: (@MainActor () async -> Void)?
    private let isPendingResolution: Bool
    private let onToggleResolved: (@MainActor () async -> Void)?

    private var isExpanded: Bool {
        expandOverrides.last ?? (thread.isResolved == false && isPendingResolution == false)
    }

    private var anchor: String {
        thread.path + (thread.line.map { ":" + String($0) } ?? "")
    }

    private var status: String {
        if thread.isResolved {
            "Resolved"
        } else if isPendingResolution {
            "On next push"
        } else {
            if localReviewer == nil {
                "GitHub"
            } else {
                "Local review"
            }
        }
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

    @ViewBuilder private var conversationIcon: some View {
        if let localReviewer {
            Image(localReviewer.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityLabel(localReviewer.displayName + " local review")
        } else if isPendingResolution, thread.isResolved == false {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Will resolve after the next confirmed push")
                .hoverHelp("Pending resolution on the next push; new comments cancel it")
        } else {
            Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                .foregroundStyle(thread.isResolved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityLabel(thread.isResolved ? "Resolved GitHub conversation" : "Open GitHub conversation")
        }
    }

    @ViewBuilder private var resolveButton: some View {
        // A REST-fallback thread carries no id to resolve.
        if thread.resolveID.isEmpty == false || localReviewer != nil,
           isPendingResolution == false || thread.isResolved,
           isUpdatingResolution == false, let onToggleResolved
        {
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

    @ViewBuilder private var resolveOnPushButton: some View {
        if thread.isResolved == false, thread.resolveID.isEmpty == false, let onToggleResolveOnPush {
            BusyButton(isPendingResolution ? "Cancel" : "Resolve on push", busy: "Updating") {
                isUpdatingResolution = true
                defer { isUpdatingResolution = false }
                await onToggleResolveOnPush()
            }
            .controlSize(.small)
            .hoverHelp(isPendingResolution
                ? "Cancel resolution on the next push"
                : "Resolve this conversation after GitHub confirms the next push")
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(thread.asText, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .accessibilityLabel("Copy this conversation")
        }
        .buttonStyle(.borderless)
        .hoverHelp("Copy this conversation, with its file and line, to the clipboard")
    }

    private var collapseToggle: some View {
        Button {
            expandOverrides = [isExpanded == false]
        } label: {
            HStack(spacing: Self.spacing) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .interfaceFont(.caption)
                conversationIcon
                Text(thread.comments.first?.author ?? "")
                    .interfaceFont(.callout, weight: .semibold)
                Text(status)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                Text(anchor)
                    .interfaceFont(.callout, monospaced: true)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isExpanded ? "Collapse" : "Expand") + " conversation at " + anchor)
        .accessibilityValue(thread.isResolved || isPendingResolution ? status : "Unresolved")
        .hoverHelp(isExpanded ? "Collapse this conversation" : "Expand this conversation to read or reopen it")
    }

    /// The disclosure header stays interactive after resolution.
    private var header: some View {
        HStack(spacing: Self.spacing) {
            collapseToggle
            copyButton
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

    private static func fenced(_ code: String) -> String {
        let fence = String(
            repeating: "`", count: max(minimumFence, (code.matches(of: /`+/).map(\.output.count).max() ?? 0) + 1),
        )
        return fence + "\n" + code + "\n" + fence
    }
}
