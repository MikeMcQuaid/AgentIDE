import AppKit

// NSTextView ranges are UTF-16 offsets, so NSString is the correct
// arithmetic here, not String.
// swiftlint:disable legacy_objc_type

// MARK: - LineNumberRuler

/// A minimal line-number ruler for an `NSTextView`.
final class LineNumberRuler: NSRulerView {
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

    /// The one-based lines with uncommitted changes, each marked
    /// with a bar down the gutter's inner edge: a tinted number said
    /// the same thing but could not be read down a scrolling file,
    /// which is the whole use of a change bar.
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

            if changedLines.contains(line) {
                NSColor.controlAccentColor.setFill()
                NSRect(
                    x: ruleThickness - Self.barWidth,
                    y: labelY,
                    width: Self.barWidth,
                    height: rect.height,
                ).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let label = NSAttributedString(string: String(line), attributes: attributes)
            let labelX = ruleThickness - label.size().width - Self.padding - Self.barWidth
            label.draw(at: NSPoint(x: labelX, y: labelY))
            index = NSMaxRange(lineRange)
            line += 1
        }
    }

    // MARK: Private

    private static let thickness: CGFloat = 38
    private static let fontSize: CGFloat = 9
    private static let padding: CGFloat = 4

    /// The change bar's width, on the gutter's inner edge where it
    /// sits against the code it belongs to.
    private static let barWidth: CGFloat = 2
}

// MARK: - Line arithmetic

extension NSString {
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
