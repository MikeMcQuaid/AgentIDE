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
        body.isEmpty ? subject : subject + "\n\n" + body
    }

    // MARK: Private

    private static let footerPadding: CGFloat = 8
    private static let commitListSpacing: CGFloat = 4
    /// git's conventional commit message widths.
    private static let subjectLimit = 50
    private static let bodyLimit = 72

    private static let messageHeightRange: ClosedRange<Double> = 60 ... 400
    private static let fieldInset: CGFloat = 5
    private static let resizeHandleHeight: CGFloat = 7

    /// The footer's height, dragged by the handle above it and
    /// persisted like the pane widths.
    @AppStorage("reviewMessageHeight")
    private var messageHeight = 88.0
    @State private var messageDragBase: Double?

    /// The commit listing coloured like git log: hashes orange,
    /// subjects bold and the trailing ref decorations green, all in
    /// one attributed block so selection still spans lines.
    private var styledCommits: AttributedString {
        var whole = AttributedString()
        for (index, line) in model.branchCommits.enumerated() {
            if index > 0 {
                whole += AttributedString("\n")
            }
            whole += Self.styledCommitLine(line)
        }
        return whole
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
                        Text(styledCommits)
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
                messageEditor
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
                    BusyButton("Commit", busy: "Committing", disabled: canCommit == false, action: onCommit)
                        .hoverHelp("Commit everything uncommitted; enabled on the uncommitted scope with changes")
                    BusyButton(
                        "Amend",
                        busy: "Amending",
                        disabled: model.showsUncommitted || model.messageEdited == false,
                    ) { await model.saveCommitMessage() }
                        .hoverHelp("Rewrite the last commit's message; dimmed until the text differs from it")
                }
            }
            .padding(Self.footerPadding)
        }
    }

    /// The subject over the body, split by a rule; the blank
    /// separator line git expects stays out of sight and reappears
    /// on save.
    private var messageEditor: some View {
        VStack(spacing: 0) {
            TextField("Subject", text: subjectBinding)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .padding(Self.fieldInset)
                .overlay(alignment: .topLeading) { columnRule(at: Self.subjectLimit, inset: Self.fieldInset) }
                .hoverHelp("The commit subject; git convention keeps it at most 50 characters")
            Divider()
            TextEditor(text: bodyBinding)
                .font(.body.monospaced())
                .frame(height: messageHeight)
                .overlay(alignment: .topLeading) { columnRule(at: Self.bodyLimit, inset: Self.fieldInset) }
                .hoverHelp("The commit body; git convention wraps lines at 72 characters")
        }
        .border(.separator)
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

    private static func styledCommitLine(_ line: String) -> AttributedString {
        let hashEnd = line.firstIndex(of: " ") ?? line.endIndex
        var hash = AttributedString(String(line[..<hashEnd]))
        hash.foregroundColor = .orange
        var rest = String(line[hashEnd...])
        var trailing = ""
        if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
            trailing = String(rest[open.lowerBound...])
            rest = String(rest[..<open.lowerBound])
        }
        var subject = AttributedString(rest)
        subject.font = .caption.monospaced().weight(.semibold)
        var decorations = AttributedString(trailing)
        decorations.foregroundColor = .green
        return hash + subject + decorations
    }
}
