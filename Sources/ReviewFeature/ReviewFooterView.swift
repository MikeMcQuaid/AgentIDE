import SwiftUI
import TerminalUI

/// The review pane's bottom half: the resizable commit message
/// editor with its column guides on the single-commit scopes, or
/// the commits-under-review list on the multi-commit ones.
struct ReviewFooterView: View {
    // MARK: Internal

    @Bindable var model: ReviewModel

    /// Commits everything the agent left uncommitted.
    let onCommit: @MainActor () async -> Void

    /// Whether Commit applies: the uncommitted scope with changes.
    let canCommit: Bool

    /// The drag handle over the footer itself.
    var body: some View {
        VStack(spacing: 0) {
            messageResizeHandle
            content
        }
    }

    // MARK: Private

    private static let footerPadding: CGFloat = 8
    private static let commitListSpacing: CGFloat = 4
    /// git's conventional commit message widths.
    private static let subjectLimit = 50
    private static let bodyLimit = 72

    private static let messageHeightRange: ClosedRange<Double> = 60 ... 400
    private static let resizeHandleHeight: CGFloat = 7

    /// The footer's height, dragged by the handle above it and
    /// persisted like the pane widths.
    @AppStorage("reviewMessageHeight")
    private var messageHeight = 88.0
    @State private var messageDragBase: Double?

    /// A slim grab area over the divider: dragging resizes the
    /// commit message or commit list pane, like the window's pane
    /// dividers.
    private var messageResizeHandle: some View {
        Divider()
            .frame(maxWidth: .infinity)
            .frame(height: Self.resizeHandleHeight)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = messageDragBase ?? messageHeight
                        messageDragBase = base
                        let dragged = base - value.translation.height
                        messageHeight = min(
                            max(dragged, Self.messageHeightRange.lowerBound),
                            Self.messageHeightRange.upperBound,
                        )
                    }
                    .onEnded { _ in messageDragBase = nil },
            )
            .hoverHelp("Drag to resize the commit message pane")
    }

    /// Last commit scope edits the message; the multi-commit scopes
    /// list every commit under review instead.
    @ViewBuilder private var content: some View {
        if model.scope == .branch || model.scope == .upstream {
            VStack(alignment: .leading, spacing: Self.commitListSpacing) {
                Text("Commits under review").font(.headline)
                ScrollView([.vertical, .horizontal]) {
                    // One text block, not a row per commit: dragging
                    // then selects across lines, so hashes and whole
                    // ranges copy. Decorations name where each commit
                    // sits in the local and remote log.
                    // The listing always carries the base commit as
                    // its final row, so one row means no commits of
                    // the branch's own.
                    if model.branchCommits.count <= 1 {
                        Text("No commits beyond the base branch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.branchCommits.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: messageHeight)
            }
            .padding(Self.footerPadding)
        } else {
            VStack(alignment: .leading, spacing: Self.footerPadding) {
                TextEditor(text: $model.commitMessage)
                    .font(.body.monospaced())
                    .frame(height: messageHeight)
                    .border(.separator)
                    .overlay(alignment: .topLeading) { messageGuides }
                    .hoverHelp(
                        "The full commit message; the guides mark 50 columns for the subject and 72 for the body",
                    )
                HStack {
                    BusyButton("Commit", busy: "Committing", disabled: canCommit == false, action: onCommit)
                        .hoverHelp("Commit everything uncommitted; enabled on the uncommitted scope with changes")
                    BusyButton(
                        "Amend",
                        busy: "Amending",
                        disabled: model.showsUncommitted || model.messageEdited == false,
                    ) { await model.saveCommitMessage() }
                        .hoverHelp("Rewrite the last commit's message; dimmed until the text differs from it")
                    messageLengths
                    if let status = model.status {
                        // Selectable so failures can be copied out.
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
            }
            .padding(Self.footerPadding)
        }
    }

    /// Vertical rules at git's conventional 50 and 72 column widths,
    /// positioned by the editor's monospaced character width.
    private var messageGuides: some View {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Text measurement is an AppKit API; NSString is its input.
        // swiftlint:disable:next legacy_objc_type
        let sample = "M" as NSString
        let size = sample.size(withAttributes: [.font: font])
        let inset: CGFloat = 5
        // The 50-column subject rule marks only the first line; the
        // 72-column body rule runs the rest of the editor.
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: size.height)
                .offset(x: inset + size.width * CGFloat(Self.subjectLimit), y: inset)
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
                .offset(x: inset + size.width * CGFloat(Self.bodyLimit))
        }
        .allowsHitTesting(false)
    }

    /// Live counts against the conventional widths, red when over.
    private var messageLengths: some View {
        let lines = model.commitMessage.split(separator: "\n", omittingEmptySubsequences: false)
        let subject = lines.first.map(String.init) ?? ""
        let widestBody = lines.dropFirst().map(\.count).max() ?? 0
        return HStack(spacing: Self.footerPadding) {
            Text("subject \(subject.count)/\(Self.subjectLimit)")
                .foregroundStyle(subject.count > Self.subjectLimit ? .red : .secondary)
            Text("body \(widestBody)/\(Self.bodyLimit)")
                .foregroundStyle(widestBody > Self.bodyLimit ? .red : .secondary)
        }
        .font(.caption.monospaced())
        .hoverHelp("git convention: subjects at most 50 characters, body lines wrapped at 72")
    }
}
