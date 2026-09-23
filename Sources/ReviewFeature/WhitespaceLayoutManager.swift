import AppKit
import CoreText
import TerminalUI

/// Draws spaces and tabs as visible glyphs in the shared light
/// whitespace tone, matching the review diff. Nonisolated to match
/// `NSLayoutManager`, which AppKit drives itself on the main thread.
///
/// Indented code is mostly spaces, so this runs for most of every
/// screen on every frame: the two glyphs are laid out once as Core
/// Text lines and drawn straight into the context, where an
/// attributed string drawn per space built and threw away a text
/// system each time and made scrolling stutter.
final nonisolated class WhitespaceLayoutManager: NSLayoutManager {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = unsafe textStorage, let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        // The storage's own string: bridging `string` to Swift copies
        // the whole document on every draw.
        let text = storage.mutableString
        let font = CodeStyle.nsFont
        if symbols?.font != font {
            symbols = Symbols(font: font)
        }
        guard let symbols else {
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        // Core Text draws the right way up in the flipped view, and
        // takes the tone from the context so it follows the
        // appearance the view is drawing in.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setFillColor(CodeStyle.whitespaceNSColour.cgColor)
        let characters = unsafe characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for index in characters.location ..< NSMaxRange(characters) {
            let line: CTLine
            switch text.character(at: index) {
            case Self.space:
                line = symbols.space

            case Self.tab:
                line = symbols.tab

            default:
                continue
            }
            let glyphIndex = glyphIndexForCharacter(at: index)
            let fragment = unsafe lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            // A glyph's location within its fragment is its baseline,
            // which is where a Core Text line is drawn from.
            let position = location(forGlyphAt: glyphIndex)
            context.textPosition = CGPoint(
                x: origin.x + fragment.minX + position.x,
                y: origin.y + fragment.minY + position.y,
            )
            CTLineDraw(line, context)
        }
    }

    // MARK: Private

    /// The two glyphs laid out once per font.
    private struct Symbols {
        // MARK: Lifecycle

        init(font: NSFont) {
            self.font = font
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            space = CTLineCreateWithAttributedString(NSAttributedString(string: "·", attributes: attributes))
            tab = CTLineCreateWithAttributedString(NSAttributedString(string: "⇥", attributes: attributes))
        }

        // MARK: Internal

        let font: NSFont
        let space: CTLine
        let tab: CTLine
    }

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09

    private var symbols: Symbols?
}
