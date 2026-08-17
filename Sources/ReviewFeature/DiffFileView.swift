import AgentIDEData
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
                    hunkView(hunkIndex: hunkIndex, hunk: hunk)
                }
            }
        }
        .padding(.bottom, isCollapsed ? Self.collapsedPadding : Self.filePadding)
    }

    // MARK: Private

    private static let collapsedPadding: CGFloat = 1

    private static let lineSpacing: CGFloat = 2
    private static let gutterSpacing: CGFloat = 6
    private static let selectionBarWidth: CGFloat = 3
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

    /// Numbers and markers sit in a tappable gutter while the code
    /// itself is one selectable text block, so dragging copies
    /// several lines without picking up `-`/`+` or line numbers.
    private func hunkView(hunkIndex: Int, hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart) +\(hunk.newStart) @@")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(alignment: .top, spacing: Self.gutterSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(numbered(hunk).enumerated()), id: \.offset) { lineIndex, entry in
                        gutterRow(hunkIndex: hunkIndex, lineIndex: lineIndex, entry: entry)
                    }
                }
                .hoverHelp("Click a changed line's number to select it for rejection")
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(hunkText(hunk))
                        .font(CodeStyle.font)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
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

    /// The hunk's code as one attributed string: syntax colours per
    /// token and change backgrounds per line, markers excluded so
    /// copies paste cleanly.
    private func hunkText(_ hunk: DiffHunk) -> AttributedString {
        var result = AttributedString()
        for (index, line) in hunk.lines.enumerated() {
            result += lineText(line)
            if index < hunk.lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
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

// MARK: - ReviewFileListView

/// The review pane's file list: collapsible diffs, or inline
/// editors in the uncommitted scope so fixes are typed directly.
struct ReviewFileListView: View {
    // MARK: Internal

    let model: ReviewModel
    let worktreePath: String
    let service: SessionService

    /// Whether files start collapsed (the Hide All display mode);
    /// the per-file carets override it.
    let hideAllByDefault: Bool

    @Binding var collapseOverrides: [String: Bool]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(model.files) { file in
                    fileSection(file)
                }
            }
            .padding(Self.spacing)
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let editorMinimumHeight: CGFloat = 240
    private static let editorMaximumHeight: CGFloat = 420

    @ViewBuilder
    private func fileSection(_ file: DiffFile) -> some View {
        // Every scope leads with the diff, uncommitted included: it
        // once showed the whole file in an editor instead, which read
        // as a broken diff. Uncommitted files keep that editor for
        // fixing in place, below their diff.
        DiffFileView(
            file: file,
            model: model,
            isCollapsed: isCollapsed(file),
            onToggleCollapse: { toggleCollapse(file) },
            onEdit: {
                FileOpener.open(relativePath: file.path, line: nil, worktreePath: worktreePath)
            },
        )
        if model.showsUncommitted, isCollapsed(file) == false, file.isNew == false {
            FileEditorView(
                worktreePath: worktreePath,
                relativePath: file.path,
                service: service,
                showsClose: false,
            )
            .frame(minHeight: Self.editorMinimumHeight, maxHeight: Self.editorMaximumHeight)
        }
        if isCollapsed(file) == false {
            ForEach(model.threads(for: file.path)) { thread in
                ReviewThreadRow(
                    thread: thread,
                    onEdit: {
                        FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: worktreePath)
                    },
                    onToggleResolved: { await model.toggleResolved(thread) },
                )
            }
        }
    }

    private func isCollapsed(_ file: DiffFile) -> Bool {
        // Generated files always start collapsed, whatever the
        // expand-all state says; only their own caret opens them.
        collapseOverrides[file.path] ?? (hideAllByDefault || model.isGenerated(file.path) || file.isNew)
    }

    private func toggleCollapse(_ file: DiffFile) {
        collapseOverrides[file.path] = isCollapsed(file) == false
    }
}
