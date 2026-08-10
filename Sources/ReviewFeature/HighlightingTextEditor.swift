import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

// NSTextView ranges are UTF-16 offsets, so NSString and
// NSAttributedString are the correct arithmetic here, not String.
// swiftlint:disable legacy_objc_type

// MARK: - HighlightingTextEditor

/// A code editor: monospaced NSTextView with syntax highlighting,
/// a line-number ruler, visible invisibles and an optional line to
/// jump to when it first appears.
struct HighlightingTextEditor: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>, language: SyntaxLanguage?) {
            self.text = text
            self.language = language
        }

        deinit {
            // Nothing to clean up.
        }

        // MARK: Internal

        var text: Binding<String>
        let language: SyntaxLanguage?
        var didJump = false

        static func highlight(_ view: NSTextView, language: SyntaxLanguage?) {
            guard let language, let storage = view.textStorage else {
                return
            }

            let selection = view.selectedRanges
            let content = view.string as NSString
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: content.length))
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.textColor,
                range: NSRange(location: 0, length: content.length),
            )
            // One backend for every surface: the same engine the diff
            // uses classifies the whole document here.
            let ranges = CodeHighlighter.documentRanges(in: view.string, language: language)
            for (range, kind) in ranges where NSMaxRange(range) <= content.length {
                storage.addAttribute(.foregroundColor, value: colour(for: kind), range: range)
            }
            storage.endEditing()
            view.selectedRanges = selection
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = view.string
            Self.highlight(view, language: language)
        }

        // MARK: Private

        private static func colour(for kind: SyntaxToken.Kind) -> NSColor {
            switch kind {
            case .keyword:
                .systemPurple

            case .string:
                .systemRed

            case .comment:
                .systemGreen

            case .number:
                .systemBlue

            case .plain:
                .textColor
            }
        }
    }

    @Binding var text: String

    let language: SyntaxLanguage?
    let jumpToLine: Int?
    var changedLines: Set<Int> = []

    func makeNSView(context: Context) -> NSScrollView {
        // A hand-built text stack, because the layout manager draws
        // whitespace itself in the shared light tone the diff uses.
        let storage = NSTextStorage()
        let layoutManager = WhitespaceLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = NSTextView(frame: .zero, textContainer: container)
        view.autoresizingMask = .width
        view.isVerticallyResizable = true
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.font = CodeStyle.nsFont
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = view
        scroll.hasVerticalRuler = true
        let ruler = LineNumberRuler(textView: view)
        ruler.changedLines = changedLines
        scroll.verticalRulerView = ruler
        scroll.rulersVisible = true
        Coordinator.highlight(view, language: language)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else {
            return
        }

        if view.string != text {
            view.string = text
            Coordinator.highlight(view, language: language)
        }
        if let jumpToLine, context.coordinator.didJump == false {
            context.coordinator.didJump = true
            jump(to: jumpToLine, in: view)
        }
        if let ruler = scroll.verticalRulerView as? LineNumberRuler {
            ruler.changedLines = changedLines
        }
        scroll.verticalRulerView?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    // MARK: Private

    /// Scrolls to and selects a one-based line.
    private func jump(to line: Int, in view: NSTextView) {
        let lines = view.string.split(separator: "\n", omittingEmptySubsequences: false)
        let previous = lines.prefix(max(0, line - 1))
        let location = previous.reduce(0) { $0 + ($1 as NSString).length + 1 }
        let length = line <= lines.count ? (String(lines[line - 1]) as NSString).length : 0
        let range = NSRange(location: min(location, (view.string as NSString).length), length: length)
        view.scrollRangeToVisible(range)
        view.setSelectedRange(range)
    }
}

// MARK: - WhitespaceLayoutManager

/// Draws spaces and tabs as visible glyphs in the shared light
/// whitespace tone, matching the review diff. Nonisolated to match
/// `NSLayoutManager`, which AppKit drives itself on the main thread.
private final nonisolated class WhitespaceLayoutManager: NSLayoutManager {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else {
            return
        }

        let text = storage.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CodeStyle.nsFont,
            .foregroundColor: CodeStyle.whitespaceNSColour,
        ]
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for index in characters.location ..< NSMaxRange(characters) {
            let symbol: String? =
                switch text.character(at: index) {
                case Self.space:
                    "·"

                case Self.tab:
                    "⇥"

                default:
                    nil
                }
            guard let symbol else {
                continue
            }

            let glyphIndex = glyphIndexForCharacter(at: index)
            let fragment = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let position = location(forGlyphAt: glyphIndex)
            let point = NSPoint(x: origin.x + fragment.minX + position.x, y: origin.y + fragment.minY)
            NSAttributedString(string: symbol, attributes: attributes).draw(at: point)
        }
    }

    // MARK: Private

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
}

// MARK: - LineNumberRuler

/// A minimal line-number ruler for an `NSTextView`.
private final class LineNumberRuler: NSRulerView {
    // MARK: Lifecycle

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness
        // The ruler must never paint outside its strip; unclipped it
        // bled its separator over neighbouring views.
        wantsLayer = true
        layer?.masksToBounds = true
    }

    deinit {
        // Nothing to clean up.
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("LineNumberRuler is created in code only")
    }

    // MARK: Internal

    /// The one-based lines with uncommitted changes, drawn in a
    /// warning tint so edits stand out in the gutter.
    var changedLines: Set<Int> = []

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let view = clientView as? NSTextView,
              let layoutManager = view.layoutManager,
              let container = view.textContainer
        else {
            return
        }

        let visible = layoutManager.glyphRange(forBoundingRect: view.visibleRect, in: container)
        let content = view.string as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: Self.fontSize, weight: .regular)

        // Labels clip to the ruler so nothing paints over the text or
        // outside the visible strip.
        NSBezierPath(rect: bounds).setClip()

        var line = content.lineNumber(at: visible.location)
        var index = content.lineStart(at: visible.location)
        while index < NSMaxRange(visible) {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let labelY = rect.minY + view.textContainerInset.height - view.visibleRect.minY
            guard labelY >= 0, labelY <= bounds.height else {
                index = NSMaxRange(lineRange)
                line += 1
                continue
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: changedLines.contains(line)
                    ? NSColor.systemOrange
                    : NSColor.secondaryLabelColor,
            ]
            let label = NSAttributedString(string: String(line), attributes: attributes)
            let labelX = ruleThickness - label.size().width - Self.padding
            label.draw(at: NSPoint(x: labelX, y: labelY))
            index = NSMaxRange(lineRange)
            line += 1
        }
    }

    // MARK: Private

    private static let thickness: CGFloat = 36
    private static let fontSize: CGFloat = 9
    private static let padding: CGFloat = 4
}

// MARK: - Line arithmetic

private extension NSString {
    /// The one-based line number containing a character index.
    func lineNumber(at location: Int) -> Int {
        var line = 1
        var index = 0
        while index < min(location, length) {
            index = NSMaxRange(lineRange(for: NSRange(location: index, length: 0)))
            line += 1
            if index > location {
                return line - 1
            }
        }
        return line
    }

    /// The character index starting the line containing `location`.
    func lineStart(at location: Int) -> Int {
        lineRange(for: NSRange(location: min(location, length), length: 0)).location
    }
}

// swiftlint:enable legacy_objc_type
