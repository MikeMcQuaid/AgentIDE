import AppKit
import TerminalUI

// MARK: - LineNumberRuler

/// A minimal line-number ruler for an `NSTextView`. Every scroll
/// redraws it, so a draw reads only what is on screen: where the
/// lines start is indexed once per edit (`LineIndex`), the label
/// font once per size change, and nothing walks the document.
final class LineNumberRuler: NSRulerView {
    // MARK: Lifecycle

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        matchCodeSize()
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

    /// The one-based lines with uncommitted changes, each marked
    /// with a bar down the gutter's inner edge: a tinted number said
    /// the same thing but could not be read down a scrolling file,
    /// which is the whole use of a change bar.
    var changedLines: Set<Int> = [] {
        didSet {
            if oldValue != changedLines {
                needsDisplay = true
            }
        }
    }

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let view = clientView as? NSTextView,
              let layoutManager = unsafe view.layoutManager,
              let container = unsafe view.textContainer,
              let storage = unsafe view.textStorage
        else {
            return
        }

        let glyphs = layoutManager.glyphRange(forBoundingRect: view.visibleRect, in: container)
        let visible = unsafe layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // The storage's own string, never `view.string`: bridging
        // that to Swift copies the whole document, once per frame.
        let content = storage.mutableString
        let starts = lineStarts ?? LineIndex.starts(in: content)
        lineStarts = starts
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Labels clip to the ruler so nothing paints over the text or
        // outside the visible strip.
        NSBezierPath(rect: bounds).setClip()

        var line = LineIndex.line(at: visible.location, starts: starts)
        var index = starts[line - 1]
        while index < NSMaxRange(visible) {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = unsafe layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let labelY = rect.minY + view.textContainerInset.height - view.visibleRect.minY
            guard labelY >= 0, labelY <= bounds.height else {
                index = NSMaxRange(lineRange)
                line += 1
                continue
            }

            if changedLines.contains(line) {
                NSColor.controlAccentColor.setFill()
                NSRect(
                    x: ruleThickness - Self.barWidth,
                    y: labelY,
                    width: Self.barWidth,
                    height: rect.height,
                ).fill()
            }
            let label = NSAttributedString(string: String(line), attributes: attributes)
            let labelX = ruleThickness - label.size().width - Self.padding - Self.barWidth
            label.draw(at: NSPoint(x: labelX, y: labelY))
            index = NSMaxRange(lineRange)
            line += 1
        }
    }

    /// Forgets where the lines start, for the next draw to index
    /// again: an edit is what moves them.
    func textChanged() {
        lineStarts = nil
        needsDisplay = true
    }

    /// Widens the gutter with the code beside it, and sizes the
    /// numbers to keep the proportion their original size had to
    /// the original code size. Read here, once per change, rather
    /// than from the preferences on every draw.
    func matchCodeSize() {
        let codeScale = CodeStyle.pointSize / CodeStyle.defaultPointSize
        guard codeScale != scale else {
            return
        }

        scale = codeScale
        ruleThickness = Self.thickness * codeScale
        labelFont = NSFont.monospacedDigitSystemFont(ofSize: Self.baseFontSize * codeScale, weight: .regular)
        needsDisplay = true
    }

    // MARK: Private

    private static let thickness: CGFloat = 38
    private static let padding: CGFloat = 4
    private static let baseFontSize: CGFloat = 9

    /// The change bar's width, on the gutter's inner edge where it
    /// sits against the code it belongs to.
    private static let barWidth: CGFloat = 2

    /// Where each line starts, indexed on the first draw after an
    /// edit and kept until the next; nil is "not indexed since the
    /// edit", which an empty document's index, `[0]`, cannot say.
    private var lineStarts: [Int]? // swiftlint:disable:this discouraged_optional_collection

    private var scale: CGFloat = 0
    private var labelFont: NSFont = .monospacedDigitSystemFont(ofSize: baseFontSize, weight: .regular)
}
