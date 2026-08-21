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
        .font(.caption.monospaced())
    }
}

// MARK: - DiffFileView

/// One file's hunks with tappable, selectable changed lines, hidden
/// behind the caret when collapsed.
struct DiffFileView: View {
    // MARK: Internal

    static let statSpacing: CGFloat = 4

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

    /// A hunk's lines as the file holds them: the displayed text
    /// stands a space in for a blank line so its change colour has
    /// something to paint, and copying that would put a space where
    /// the file has nothing at all.
    static func copyText(of hunk: DiffHunk) -> String {
        hunk.lines.map(\.content).joined(separator: "\n")
    }

    // MARK: Private

    private static let collapsedPadding: CGFloat = 1

    private static let lineSpacing: CGFloat = 2
    private static let gutterSpacing: CGFloat = 6
    private static let selectionBarWidth: CGFloat = 3

    /// Enough to find a match at a glance without hiding the code.
    private static let foundOpacity = 0.45
    private static let changeOpacity = 0.15
    private static let selectedOpacity = 0.35
    private static let filePadding: CGFloat = 8
    private static let numberWidth = 4

    /// The file's name, its new-file marker, diffstat and the
    /// copy and edit actions.
    private var headerRow: some View {
        HStack {
            FileCollapseCaret(isCollapsed: isCollapsed, onToggle: onToggleCollapse)
            Text(file.path).font(.headline.monospaced())
            if file.isNew {
                Text("new file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .hoverHelp("Added or untracked: the whole file is the diff, so it starts collapsed")
            }
            Spacer()
            DiffStatText(additions: file.additions, deletions: file.deletions)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .accessibilityLabel("Copy file path")
            }
            .buttonStyle(.borderless)
            .hoverHelp("Copy this file's path to the clipboard")
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .accessibilityLabel("Edit file")
            }
            .buttonStyle(.borderless)
            .hoverHelp("Open this file in the built-in editor for review-time fixes")
        }
    }

    /// Numbers and markers sit in a tappable gutter beside each
    /// line, which wraps to the pane's width as the editor's does:
    /// a long line is read rather than scrolled sideways to. Each
    /// line is its own text, so Copy hunk rather than a drag is
    /// what takes several lines at once, markers and numbers left
    /// behind.
    private func hunkView(hunkIndex: Int, hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart) +\(hunk.newStart) @@")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(Array(numbered(hunk).enumerated()), id: \.offset) { lineIndex, entry in
                HStack(alignment: .top, spacing: Self.gutterSpacing) {
                    gutterRow(hunkIndex: hunkIndex, lineIndex: lineIndex, entry: entry)
                        .hoverHelp("Click a changed line's number to select it for rejection")
                    Text(lineText(entry.line))
                        .font(CodeStyle.font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

    /// One gutter line: numbers and the change marker, tappable on
    /// changed lines and carrying the rejection selection bar. Only
    /// changed lines carry the gesture and button trait.
    @ViewBuilder
    private func gutterRow(
        hunkIndex: Int,
        lineIndex: Int,
        entry: (line: DiffLine, numbers: String),
    ) -> some View {
        let selected = isSelected(hunkIndex: hunkIndex, lineIndex: lineIndex)
        let label = Text(entry.numbers + " " + Self.marker(for: entry.line.kind))
            .font(CodeStyle.font)
            .foregroundStyle(.secondary)
            .background(Self.background(for: entry.line.kind, selected: selected))
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(.blue).frame(width: Self.selectionBarWidth)
                }
            }
        if entry.line.kind == .context {
            label
        } else {
            label
                .contentShape(Rectangle())
                .onTapGesture {
                    model.toggle(file: file, selection: DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex))
                }
                .accessibilityAddTraits(.isButton)
        }
    }

    private static func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .context:
            " "

        case .addition:
            "+"

        case .deletion:
            "-"
        }
    }

    private static func background(for kind: DiffLine.Kind, selected: Bool) -> Color {
        let opacity = selected ? Self.selectedOpacity : Self.changeOpacity
        switch kind {
        case .context:
            return .clear

        case .addition:
            return .green.opacity(opacity)

        case .deletion:
            return .red.opacity(opacity)
        }
    }

    private static func pad(_ number: Int?) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, numberWidth - text.count)) + text
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
        }
    }

    /// One line's text: a whitespace tint covers tabs and the
    /// trailing whitespace run, so whitespace-only changes stay
    /// reviewable while copies remain character-exact (a background
    /// rather than the substitute glyphs the editor uses).
    private func lineText(_ line: DiffLine) -> AttributedString {
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
                piece.foregroundColor = HighlightedLine.colour(for: token.kind)
                piece.backgroundColor = run.isMarked ? CodeStyle.whitespaceColour : base
                content += piece
            }
            offset += token.text.count
        }
        Self.markFound(model.findRanges(in: line.content), of: line.content, in: &content)
        if content.characters.isEmpty {
            var blank = AttributedString(" ")
            blank.backgroundColor = base
            content = blank
        }
        return content
    }

    /// Joins each line with its old and new line numbers; deletions
    /// advance only the old side, additions only the new.
    private func numbered(_ hunk: DiffHunk) -> [(line: DiffLine, numbers: String)] {
        var old = hunk.oldStart
        var new = hunk.newStart
        return hunk.lines.map { line in
            let numbers: String
            switch line.kind {
            case .context:
                numbers = Self.pad(old) + " " + Self.pad(new)
                old += 1
                new += 1

            case .deletion:
                numbers = Self.pad(old) + " " + Self.pad(nil)
                old += 1

            case .addition:
                numbers = Self.pad(nil) + " " + Self.pad(new)
                new += 1
            }
            return (line, numbers)
        }
    }

    private func isSelected(hunkIndex: Int, lineIndex: Int) -> Bool {
        model.selections[file.path]?
            .contains(DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex)) ?? false
    }
}
