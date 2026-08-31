import AgentIDEDomain
import AppKit

// NSTextView ranges are UTF-16 offsets, so NSString is the correct
// arithmetic here, not String.
// swiftlint:disable legacy_objc_type

/// The editor's text view: Tab indents at the file's own unit,
/// Cmd-/ toggles the language's line comment and Option with the
/// arrows moves lines, each through the pure `LineEditing` rules
/// and each a single undoable edit.
final class EditingTextView: NSTextView {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    /// The open file's language, which is what knows the comment
    /// prefix; set once at creation, like the file itself.
    var language: SyntaxLanguage?

    override func insertTab(_: Any?) {
        let unit = LineEditing.indentationUnit(of: documentLines)
        guard selectedRange().length > 0 else {
            insertText(unit, replacementRange: selectedRange())
            return
        }

        transformSelectedLines { LineEditing.indented($0, unit: unit) }
    }

    override func insertBacktab(_: Any?) {
        transformSelectedLines { LineEditing.dedented($0, unit: LineEditing.indentationUnit(of: documentLines)) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "/" {
            toggleComment()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Arrows also carry the function and numeric-pad flags, so
        // only the modifiers a hand chooses are compared.
        let chosen = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (chosen, event.keyCode) {
        case (.option, Self.upArrowKey):
            moveLines(upwards: true)

        case (.option, Self.downArrowKey):
            moveLines(upwards: false)

        default:
            super.keyDown(with: event)
        }
    }

    /// Toggles the language's line comment across the selected
    /// lines; a language without one changes nothing.
    func toggleComment() {
        guard let prefix = LineEditing.commentPrefix(for: language) else {
            return
        }

        transformSelectedLines { LineEditing.toggledComment($0, prefix: prefix) }
    }

    /// Moves the selected lines one line up or down, keeping them
    /// selected where they land; the file's edge is a quiet no-op.
    func moveLines(upwards: Bool) {
        let text = string as NSString
        let paragraphs = text.lineRange(for: selectedRange())
        let neighbour: NSRange
        if upwards {
            guard paragraphs.location > 0 else {
                return
            }

            neighbour = text.lineRange(for: NSRange(location: paragraphs.location - 1, length: 0))
        } else {
            guard NSMaxRange(paragraphs) < text.length else {
                return
            }

            neighbour = text.lineRange(for: NSRange(location: NSMaxRange(paragraphs), length: 0))
        }
        let union = NSUnionRange(paragraphs, neighbour)
        var (lines, endsWithNewline) = blockLines(in: union)
        let inner = upwards ? 1 ..< lines.count : 0 ..< lines.count - 1
        guard let moved = LineEditing.moved(lines, in: inner, upwards: upwards) else {
            return
        }

        lines = moved.lines
        replace(union, with: lines.joined(separator: "\n") + (endsWithNewline ? "\n" : ""))
        let start = union.location + utf16Length(of: lines.prefix(moved.range.lowerBound), newlines: true)
        let length = utf16Length(of: lines[moved.range], newlines: true) - 1
        setSelectedRange(NSRange(location: start, length: max(length, 0)))
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Private

    private static let upArrowKey: UInt16 = 126
    private static let downArrowKey: UInt16 = 125

    /// The document as lines, for the indentation unit.
    private var documentLines: [String] {
        string.components(separatedBy: "\n")
    }

    /// A paragraph block as lines, with whether it closed on a
    /// newline: the final line of a file often does not.
    private func blockLines(in range: NSRange) -> ([String], Bool) {
        let block = (string as NSString).substring(with: range)
        var lines = block.components(separatedBy: "\n")
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline {
            lines.removeLast()
        }
        return (lines, endsWithNewline)
    }

    /// Rewrites the selected lines through one pure transform,
    /// leaving them selected; a transform that changes nothing
    /// leaves the selection alone too.
    private func transformSelectedLines(_ transform: ([String]) -> [String]) {
        let text = string as NSString
        let paragraphs = text.lineRange(for: selectedRange())
        let (lines, endsWithNewline) = blockLines(in: paragraphs)
        let hadSelection = selectedRange().length > 0
        let caret = selectedRange().location
        let transformed = transform(lines)
        guard transformed != lines else {
            return
        }

        let replacement = transformed.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        replace(paragraphs, with: replacement)
        let replaced = (replacement as NSString).length
        if hadSelection {
            setSelectedRange(NSRange(
                location: paragraphs.location,
                length: replaced - (endsWithNewline ? 1 : 0),
            ))
        } else {
            // The caret stays on its line, carried by the block's
            // growth and kept inside the rewritten range.
            let carried = caret + replaced - paragraphs.length
            let clamped = min(max(carried, paragraphs.location), paragraphs.location + replaced)
            setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }

    /// One undoable edit, announced so the binding and highlighting
    /// follow.
    private func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else {
            return
        }

        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
    }

    private func utf16Length(of lines: some Sequence<String>, newlines: Bool) -> Int {
        lines.reduce(0) { $0 + ($1 as NSString).length + (newlines ? 1 : 0) }
    }
}

// swiftlint:enable legacy_objc_type
