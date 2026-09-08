import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

// MARK: - FileCollapseCaret

/// The one caret that hides or shows a file's body in review lists.
struct FileCollapseCaret: View {
    // MARK: Internal

    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : Self.expandedDegrees))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Show file" : "Hide file")
        .hoverHelp(isCollapsed ? "Show this file" : "Hide this file")
    }

    // MARK: Private

    private static let expandedDegrees: Double = 90
}

// MARK: - DiffStatText

/// The compact `+n −n` insertion and deletion counts shown beside
/// diffs, green and red like every diffstat.
struct DiffStatText: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: DiffFileView.statSpacing) {
            Text("+" + String(additions)).foregroundStyle(.green)
            Text("\u{2212}" + String(deletions)).foregroundStyle(.red)
        }
        .font(.callout.monospaced())
    }
}

// MARK: - DiffFileView

/// One file's hunks with tappable, selectable changed lines, hidden
/// behind the caret when collapsed.
struct DiffFileView: View {
    // MARK: Internal

    /// A diff line with its numbers drawn.
    struct NumberedLine {
        let line: DiffLine
        let numbers: String
    }

    static let statSpacing: CGFloat = 4

    static let changeOpacity = 0.15

    /// Internal, since the selectable extension file tints its
    /// gutters with it.
    static let selectedOpacity = 0.35

    let file: DiffFile
    let model: ReviewModel
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onEdit: () -> Void

    /// The highlighter language for this file, judged by extension.
    var language: SyntaxLanguage? {
        SyntaxLanguage.language(forPath: file.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            headerRow
            if isCollapsed == false {
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                    // The find bar scrolls to a hunk, since a hunk's
                    // lines are drawn as one block of text.
                    hunkView(hunkIndex: hunkIndex, hunk: hunk)
                        .id(ReviewModel.FindTarget(file: file.path, hunk: hunkIndex).id)
                }
            }
        }
        .padding(.bottom, isCollapsed ? Self.collapsedPadding : Self.filePadding)
    }

    static func pad(_ number: Int?) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, numberWidth - text.count)) + text
    }

    /// One line's text: a whitespace tint covers tabs and the
    /// trailing whitespace run, so whitespace-only changes stay
    /// reviewable while copies remain character-exact (a background
    /// rather than the substitute glyphs the editor uses).
    func lineText(_ line: DiffLine) -> AttributedString {
        let base: Color? =
            switch line.kind {
            case .addition:
                Color.green.opacity(Self.changeOpacity)

            case .deletion:
                Color.red.opacity(Self.changeOpacity)

            case .context:
                nil
            }
        let trailingStart = line.content.count
            - line.content.reversed().prefix { $0 == " " || $0 == "\t" }.count
        var content = AttributedString()
        var offset = 0
        for token in CodeHighlighter.tokens(for: line.content, language: language) {
            for run in Self.whitespaceRuns(of: token.text, from: offset, trailingStart: trailingStart) {
                var piece = AttributedString(run.text)
                // Both scopes: Text reads the SwiftUI attributes and
                // the selectable hunk's conversion keeps only the
                // AppKit ones.
                piece.foregroundColor = HighlightedLine.colour(for: token.kind)
                piece.appKit.foregroundColor = NSColor(HighlightedLine.colour(for: token.kind))
                let background = run.isMarked ? CodeStyle.whitespaceColour : base
                piece.backgroundColor = background
                piece.appKit.backgroundColor = background.map(NSColor.init)
                content += piece
            }
            offset += token.text.count
        }
        Self.markFound(model.findRanges(in: line.content), of: line.content, in: &content)
        if content.characters.isEmpty {
            var blank = AttributedString(" ")
            blank.backgroundColor = base
            blank.appKit.backgroundColor = base.map(NSColor.init)
            content = blank
        }
        return content
    }

    /// Internal, since the selectable extension file colours its
    /// gutters from it too.
    func isSelected(hunkIndex: Int, lineIndex: Int) -> Bool {
        model.selections[file.path]?
            .contains(DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex)) ?? false
    }

    // MARK: Private

    private static let collapsedPadding: CGFloat = 1

    private static let lineSpacing: CGFloat = 2

    /// Enough to find a match at a glance without hiding the code.
    private static let foundOpacity = 0.45

    private static let filePadding: CGFloat = 8
    private static let numberWidth = 4

    /// Whether Delete is asking before removing the file.
    @State private var isConfirmingDelete = false

    /// Whether Reset is asking before putting the file back.
    @State private var isConfirmingReset = false

    /// Beside the name rather than at the end of the row: it copies
    /// that name, and among the actions it read as one of them.
    private var copyPathButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .accessibilityLabel("Copy file path")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .hoverHelp("Copy this file's path to the clipboard")
    }

    private var headerRow: some View {
        HStack {
            commitTick
            FileCollapseCaret(isCollapsed: isCollapsed, onToggle: onToggleCollapse)
            Text(file.path)
                .font(.headline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            copyPathButton
            if file.isNew {
                Text("new file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .hoverHelp("Added or untracked: the whole file is the diff")
            }
            Spacer()
            DiffStatText(additions: file.additions, deletions: file.deletions)
            // The pencil opens the editor in every scope: a diff is
            // for reading, and lines that turned into fields on a
            // click could not be selected across. Uncommitted work
            // can also be put back: a tracked file to what HEAD has,
            // a file never committed thrown away, each after asking.
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .accessibilityLabel("Edit file")
            }
            .buttonStyle(.borderless)
            .hoverHelp("Open this file in the built-in editor for review-time fixes")
            if model.showsUncommitted {
                if file.isNew {
                    deleteButton
                } else {
                    resetButton
                }
            }
        }
    }

    /// Puts a tracked file back to what HEAD has, asking first: it
    /// throws away every uncommitted change to the file, staged or
    /// not, and nothing holds a copy of those.
    private var resetButton: some View {
        Button {
            isConfirmingReset = true
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .accessibilityLabel("Reset file")
        }
        .buttonStyle(.borderless)
        .hoverHelp("Put this file back to what HEAD has, losing its uncommitted changes; asks first")
        .confirmationDialog(
            "Reset " + file.path + " to HEAD?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible,
        ) {
            Button("Reset", role: .destructive) { Task { await model.resetFile(file) } }
            Button("Cancel", role: .cancel) { isConfirmingReset = false }
        } message: {
            Text("Every uncommitted change to the file is thrown away, and nothing holds a copy.")
        }
    }

    /// Deletes a file never committed, asking first: the one action
    /// here that cannot be undone by editing, and the one a tracked
    /// file never offers, since git holds its content anyway.
    private var deleteButton: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            Image(systemName: "trash")
                .accessibilityLabel("Delete file")
        }
        .buttonStyle(.borderless)
        .hoverHelp("Delete this never-committed file from the worktree; asks first")
        .confirmationDialog(
            "Delete " + file.path + " from the worktree?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) { Task { await model.deleteFile(file) } }
            Button("Cancel", role: .cancel) { isConfirmingDelete = false }
        } message: {
            Text("The file was never committed, so this is the end of it.")
        }
    }

    /// One hunk as one selectable text in every scope, its gutter
    /// of numbers and markers at the head of each line and long
    /// lines wrapped to the pane's width as the editor's are: a drag
    /// selects across lines and a copy leaves the gutter behind.
    private func hunkView(hunkIndex: Int, hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart) +\(hunk.newStart) @@")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            selectableHunk(hunkIndex: hunkIndex, hunk: hunk)
        }
        .contextMenu { copyHunkAction(hunk) }
    }

    /// Copying a whole hunk, which wrapping took from dragging: the
    /// code alone, so it pastes as code.
    private func copyHunkAction(_ hunk: DiffHunk) -> some View {
        Button("Copy hunk") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.copyText(of: hunk), forType: .string)
        }
        .hoverHelp("Copy this hunk's lines without their numbers or change markers")
    }

    /// Splits a token into runs, marked when a character is a tab or
    /// sits in the line's trailing whitespace.
    private static func whitespaceRuns(
        of text: String,
        from offset: Int,
        trailingStart: Int,
    ) -> [(text: String, isMarked: Bool)] {
        var runs = [(text: String, isMarked: Bool)]()
        for (position, character) in text.enumerated() {
            let isWhitespace = character == " " || character == "\t"
            let marked = character == "\t" || (isWhitespace && offset + position >= trailingStart)
            if var last = runs.last, last.isMarked == marked {
                last.text.append(character)
                runs[runs.count - 1] = last
            } else {
                runs.append((String(character), marked))
            }
        }
        return runs
    }

    /// Tints what the find bar is looking for, over whatever the
    /// syntax and whitespace colouring already put there.
    private static func markFound(
        _ ranges: [Range<String.Index>],
        of line: String,
        in content: inout AttributedString,
    ) {
        let characters = content.characters
        for range in ranges {
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            let length = line.distance(from: range.lowerBound, to: range.upperBound)
            guard let from = characters.index(characters.startIndex, offsetBy: start, limitedBy: characters.endIndex),
                  let upTo = characters.index(from, offsetBy: length, limitedBy: characters.endIndex)
            else {
                return
            }

            content[from ..< upTo].backgroundColor = .yellow.opacity(Self.foundOpacity)
            content[from ..< upTo].appKit.backgroundColor = NSColor(Color.yellow.opacity(Self.foundOpacity))
        }
    }
}
