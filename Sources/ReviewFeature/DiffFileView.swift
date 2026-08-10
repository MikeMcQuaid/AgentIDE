import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - DiffFileView

/// One file's hunks with tappable, selectable changed lines.
struct DiffFileView: View {
    // MARK: Internal

    let file: DiffFile
    let model: ReviewModel
    let onEdit: () -> Void

    /// The highlighter language for this file, judged by extension.
    var language: SyntaxLanguage? {
        SyntaxLanguage.language(forPath: file.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            HStack {
                Text(file.path).font(.headline.monospaced())
                Spacer()
                Button("Edit file", action: onEdit)
                    .hoverHelp("Open this file in the built-in editor for review-time fixes")
            }
            ForEach(Array(file.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                hunkView(hunkIndex: hunkIndex, hunk: hunk)
            }
        }
        .padding(.bottom, Self.filePadding)
    }

    // MARK: Private

    private static let lineSpacing: CGFloat = 2
    private static let filePadding: CGFloat = 8
    private static let numberWidth = 4

    private func hunkView(hunkIndex: Int, hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart) +\(hunk.newStart) @@")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            ForEach(Array(numbered(hunk).enumerated()), id: \.offset) { lineIndex, entry in
                DiffLineView(
                    line: entry.line,
                    numbers: entry.numbers,
                    language: language,
                    isSelected: isSelected(hunkIndex: hunkIndex, lineIndex: lineIndex),
                ) {
                    model.toggle(
                        file: file,
                        selection: DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex),
                    )
                }
            }
        }
    }

    private static func pad(_ number: Int?) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, numberWidth - text.count)) + text
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

// MARK: - DiffLineView

/// One diff line: line numbers, change marker, highlighted content
/// with visible whitespace, tappable when changeable.
struct DiffLineView: View {
    // MARK: Internal

    let line: DiffLine
    let numbers: String
    let language: SyntaxLanguage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let text = (numberText + Text(prefix) + content)
            .font(CodeStyle.font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(.blue).frame(width: Self.selectionBarWidth)
                }
            }
        // Only changed lines are tappable, so only they carry the
        // button gesture and accessibility trait.
        if line.kind == .context {
            text
        } else {
            text
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Private

    private static let selectionBarWidth: CGFloat = 3
    private static let selectedOpacity = 0.35
    private static let unselectedOpacity = 0.15

    private var numberText: Text {
        Text(numbers + " ").foregroundStyle(.tertiary)
    }

    /// The content with syntax colours and whitespace made visible.
    private var content: Text {
        CodeHighlighter.tokens(for: line.content, language: language).reduce(Text("")) { text, token in
            text + Self.withVisibleWhitespace(token)
        }
    }

    private var prefix: String {
        switch line.kind {
        case .context:
            "  "

        case .addition:
            "+ "

        case .deletion:
            "- "
        }
    }

    private var opacity: Double {
        isSelected ? Self.selectedOpacity : Self.unselectedOpacity
    }

    private var background: Color {
        switch line.kind {
        case .context:
            .clear

        case .addition:
            .green.opacity(opacity)

        case .deletion:
            .red.opacity(opacity)
        }
    }

    /// Spaces render as faint middle dots and tabs as arrows, so
    /// stray whitespace is reviewable.
    private static func withVisibleWhitespace(_ token: SyntaxToken) -> Text {
        var parts = [Text]()
        var run = ""
        var runIsWhitespace = false

        func flush() {
            guard run.isEmpty == false else {
                return
            }

            if runIsWhitespace {
                let glyphs = run.replacing(" ", with: "·").replacing("\t", with: "⇥")
                parts.append(Text(glyphs).foregroundStyle(CodeStyle.whitespaceColour))
            } else {
                parts.append(Text(run).foregroundStyle(colour(for: token.kind)))
            }
            run = ""
        }

        for character in token.text {
            let isWhitespace = character == " " || character == "\t"
            if isWhitespace != runIsWhitespace {
                flush()
                runIsWhitespace = isWhitespace
            }
            run.append(character)
        }
        flush()
        return parts.reduce(Text(""), +)
    }

    /// The shared mapping, so diffs and editors colour identically.
    private static func colour(for kind: SyntaxToken.Kind) -> Color {
        HighlightedLine.colour(for: kind)
    }
}
