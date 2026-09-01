import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

// NSTextView renders NSAttributedString, so it is the currency here.
// swiftlint:disable legacy_objc_type

/// The read-only hunk as one selectable text: history never edits,
/// so its lines can share a view and a drag can cross them. Split
/// from the view body for length; internal rather than private
/// throughout, since the formatter deletes a private declaration
/// nothing in its own file reads.
extension DiffFileView {
    /// The gutter's character count, identical on every line since
    /// the numbers are padded.
    static var hunkGutterLength: Int {
        gutter(numbers: pad(nil) + " " + pad(nil), kind: .context).count
    }

    /// Internal, since the stacked rows draw the same markers.
    static func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .context:
            " "

        case .addition:
            "+"

        case .deletion:
            "-"
        }
    }

    /// Internal, for the same gutters.
    static func background(for kind: DiffLine.Kind, selected: Bool) -> Color {
        let opacity = selected ? selectedOpacity : changeOpacity
        switch kind {
        case .context:
            return .clear

        case .addition:
            return .green.opacity(opacity)

        case .deletion:
            return .red.opacity(opacity)
        }
    }

    /// One hunk as the selectable text view, its gutter clicks still
    /// toggling changed lines for rejection.
    func selectableHunk(hunkIndex: Int, hunk: DiffHunk) -> some View {
        let entries = numbered(hunk)
        // Bound first: the formatter rewrites a trailing closure
        // after a multiline call.
        let toggle: (Int) -> Void = { lineIndex in
            model.toggle(file: file, selection: DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex))
        }
        return DiffHunkTextView(
            text: hunkText(hunkIndex: hunkIndex, entries: entries),
            gutterLength: Self.hunkGutterLength,
            changedLines: Set(entries.indices.filter { entries[$0].line.kind != .context }),
            onToggleLine: toggle,
        )
        .hoverHelp("Drag to select across lines; a copy leaves the numbers behind. "
            + "Click a changed line's number to select it for rejection")
    }

    /// The hunk's lines as one attributed text: the gutter rides at
    /// the head of each line in the same colours the stacked rows
    /// drew, wrapped continuations indent past it, and the code
    /// keeps the colouring `lineText` already built.
    func hunkText(hunkIndex: Int, entries: [NumberedLine]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (lineIndex, entry) in entries.enumerated() {
            if lineIndex > 0 {
                text.append(NSAttributedString(string: "\n"))
            }
            text.append(gutterText(
                entry,
                selected: isSelected(hunkIndex: hunkIndex, lineIndex: lineIndex),
            ))
            text.append(NSAttributedString(lineText(entry.line)))
        }
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.font, value: CodeStyle.nsFont, range: whole)
        let style = NSMutableParagraphStyle()
        style.headIndent = gutterWidth()
        text.addAttribute(.paragraphStyle, value: style, range: whole)
        return text
    }

    // MARK: Private

    /// One line's gutter as drawn: the padded numbers, the change
    /// marker and the space keeping the code off it.
    private static func gutter(numbers: String, kind: DiffLine.Kind) -> String {
        numbers + " " + marker(for: kind) + " "
    }

    private func gutterText(_ entry: NumberedLine, selected: Bool) -> NSAttributedString {
        let gutter = NSMutableAttributedString(
            string: Self.gutter(numbers: entry.numbers, kind: entry.line.kind),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor],
        )
        let background = Self.background(for: entry.line.kind, selected: selected)
        if background != .clear {
            gutter.addAttribute(
                .backgroundColor,
                value: NSColor(background),
                range: NSRange(location: 0, length: gutter.length),
            )
        }
        return gutter
    }

    /// Where wrapped continuations start: past the gutter, under
    /// the code, measured once from the monospaced font.
    private func gutterWidth() -> CGFloat {
        let sample = String(repeating: " ", count: Self.hunkGutterLength) as NSString
        return sample.size(withAttributes: [.font: CodeStyle.nsFont]).width
    }
}

// swiftlint:enable legacy_objc_type
