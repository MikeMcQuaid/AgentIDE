import SwiftUI
import TerminalUI

/// The review pane's bottom half: the resizable commit message
/// editor with its column guides on the single-commit scopes, or
/// the commits-under-review list on the multi-commit ones.
struct ReviewFooterView: View {
    // MARK: Internal

    /// Internal so the commit listing's own file shares it.
    static let footerPadding: CGFloat = 8

    @Bindable var model: ReviewModel

    /// Commits everything the agent left uncommitted.
    let onCommit: @MainActor () async -> Void

    /// Adds it to the last commit instead.
    let onAmend: @MainActor () async -> Void

    /// Whether Commit applies: the uncommitted scope with changes.
    let canCommit: Bool

    /// The drag handle over the footer itself.
    var body: some View {
        VStack(spacing: 0) {
            messageResizeHandle
            content
        }
    }

    /// The first line of a commit message.
    static func subject(of message: String) -> String {
        message.split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
    }

    /// Everything after the subject and its blank separator line.
    static func messageBody(of message: String) -> String {
        message.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .drop(while: \.isEmpty)
            .joined(separator: "\n")
    }

    /// Rejoins the fields with the blank separator git expects.
    static func message(subject: String, body: String) -> String {
        if body.isEmpty {
            subject
        } else {
            subject + "\n\n" + body
        }
    }

    // MARK: Private

    private static let commitListSpacing: CGFloat = 4
    /// git's conventional commit message widths.
    private static let subjectLimit = 50
    private static let bodyLimit = 72

    private static let messageHeightRange: ClosedRange<Double> = 90 ... 600
    private static let fieldInset: CGFloat = 5
    private static let fieldCorner: CGFloat = 6
    private static let resizeHandleHeight: CGFloat = 7

    /// The footer's height, dragged by the handle above it and
    /// persisted like the pane widths.
    @AppStorage("reviewMessageHeight")
    private var messageHeight = 150.0
    @State private var messageDragBase: Double?

    /// Amend folds the ticked files into the last commit on the
    /// uncommitted scope, and rewrites a commit's message on the
    /// scopes that show one.
    private var canAmend: Bool {
        guard model.showsUncommitted else {
            return model.messageEdited
        }

        return canCommit && model.committingCount > 0
    }

    private var amendHelp: String {
        guard model.showsUncommitted else {
            return "Rewrite the last commit's message; dimmed until the text differs from it"
        }
        guard model.committingCount > 0 else {
            return "Tick the files to add to the last commit"
        }

        let count = model.pathsToCommit.isEmpty ? "everything uncommitted" : String(model.committingCount) + " files"
        return "Add " + count + " to the last commit, keeping its message. "
            + "A commit already pushed needs Push again, which leases the overwrite"
    }

    /// The button's own words: everything, or the count that is
    /// ticked, so what a click is about to commit is on the button.
    private var commitTitle: String {
        let committing = model.committingCount
        guard committing < model.files.count else {
            return "Commit"
        }

        return "Commit " + String(committing) + " of " + String(model.files.count)
    }

    private var commitHelp: String {
        guard model.committingCount > 0 else {
            return "Tick the files to commit; every file is ticked to begin with"
        }
        guard model.pathsToCommit.isEmpty else {
            return "Commit the ticked files, leaving the rest uncommitted"
        }

        return "Commit everything uncommitted; enabled on the uncommitted scope with changes"
    }

    private var subjectBinding: Binding<String> {
        Binding(
            get: { Self.subject(of: model.commitMessage) },
            set: { model.commitMessage = Self.message(subject: $0, body: Self.messageBody(of: model.commitMessage)) },
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { Self.messageBody(of: model.commitMessage) },
            set: { model.commitMessage = Self.message(subject: Self.subject(of: model.commitMessage), body: $0) },
        )
    }

    /// The message lengths and status beside the drafting,
    /// commit and amend actions, in click order.
    private var actionRow: some View {
        HStack {
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
            messageButtons
        }
    }

    /// Committing and amending, in click order.
    @ViewBuilder private var messageButtons: some View {
        BusyButton(
            "Amend",
            busy: "Amending",
            disabled: canAmend == false,
            action: amend,
        )
        .hoverHelp(amendHelp)
        BusyButton(
            commitTitle,
            busy: "Committing",
            prominent: true,
            disabled: canCommit == false || model.committingCount == 0,
            keepsTitle: true,
            action: onCommit,
        )
        .hoverHelp(commitHelp)
    }

    /// A slim grab area over the divider: dragging resizes the
    /// commit message or commit list pane, like the window's pane
    /// dividers.
    private var messageResizeHandle: some View {
        Divider()
            .frame(maxWidth: .infinity)
            .frame(height: Self.resizeHandleHeight)
            .contentShape(Rectangle())
            // The system's own pointer for a row edge, which holds
            // over the AppKit views either side of it; a pushed
            // `NSCursor` did not.
            .pointerStyle(.rowResize)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = messageDragBase ?? messageHeight
                        messageDragBase = base
                        // Whole points: fractional heights make the
                        // text jiggle as it re-rasterises mid-drag.
                        let dragged = (base - value.translation.height).rounded()
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
        if model.commitTarget != nil {
            VStack(alignment: .leading, spacing: Self.footerPadding) {
                singleCommitHeader
                messageEditor
            }
            .padding(Self.footerPadding)
        } else if model.scope == .branch || model.scope == .upstream {
            VStack(alignment: .leading, spacing: Self.commitListSpacing) {
                Text("Commits under review").font(.headline)
                ScrollView(.vertical) {
                    // One text block, not a row per commit: dragging
                    // then selects across lines, so hashes and whole
                    // ranges copy. Decorations name where each commit
                    // sits in the local and remote log. Long subjects
                    // wrap to the pane, as the editor and the diff do,
                    // rather than hiding off to the right.
                    // The listing always carries the base commit as
                    // its final row, so one row means no commits of
                    // the branch's own.
                    if model.hasLoaded == false {
                        Text("Listing the branch's commits…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.branchCommits.count <= 1 {
                        Text("No commits beyond the base branch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(styledCommits)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: messageHeight)
                .environment(\.openURL, OpenURLAction { url in show(commit: url) })
            }
            .padding(Self.footerPadding)
        } else {
            VStack(alignment: .leading, spacing: Self.footerPadding) {
                messageEditor
                actionRow
            }
            .padding(Self.footerPadding)
        }
    }

    /// The subject over the body, split by a rule; the blank
    /// separator line git expects stays out of sight and reappears
    /// on save.
    private var messageEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TextField("Subject", text: subjectBinding.readOnly(model.isReadOnly))
                    .readOnly(model.isReadOnly)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(Self.fieldInset)
                    .overlay(alignment: .topLeading) { columnRule(at: Self.subjectLimit, inset: Self.fieldInset) }
                    .hoverHelp("The commit subject; git convention keeps it at most 50 characters")
                draftButton
                    .padding(.trailing, Self.fieldInset)
            }
            Divider()
            TextEditor(text: bodyBinding.readOnly(model.isReadOnly))
                .readOnly(model.isReadOnly)
                .font(.body.monospaced())
                .frame(height: messageHeight)
                .overlay(alignment: .topLeading) { columnRule(at: Self.bodyLimit, inset: Self.fieldInset) }
                .hoverHelp("The commit body; git convention wraps lines at 72 characters")
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.fieldCorner))
        .overlay(RoundedRectangle(cornerRadius: Self.fieldCorner).stroke(.separator))
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
        .font(.callout.monospaced())
        .hoverHelp("git convention: subjects at most 50 characters, body lines wrapped at 72")
    }

    /// A vertical rule at a conventional column, positioned by the
    /// monospaced character width.
    private func columnRule(at limit: Int, inset: CGFloat) -> some View {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Text measurement is an AppKit API; NSString is its input.
        // swiftlint:disable:next legacy_objc_type
        let sample = "M" as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        return Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .offset(x: inset + width * CGFloat(limit))
            .allowsHitTesting(false)
    }

    /// The uncommitted scope folds files in; the scopes that show a
    /// commit rewrite its message.
    private func amend() async {
        if model.showsUncommitted {
            await onAmend()
        } else {
            await model.saveCommitMessage()
        }
    }
}
