import AppKit
import SwiftUI

/// The one code typography shared by every surface that renders
/// code: terminals, diffs, the editor and finder results.
/// Nonisolated because AppKit layout machinery reads it outside the
/// main actor's checking.
public nonisolated enum CodeStyle {
    /// The shared monospaced point size.
    public static let pointSize: CGFloat = 12

    /// The AppKit font for text views and terminals.
    public static var nsFont: NSFont {
        .monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }

    /// The SwiftUI font for diff lines and result rows.
    public static var font: Font {
        .system(size: pointSize, design: .monospaced)
    }

    /// The light tone shared by visible whitespace glyphs in the
    /// diff and the editor.
    public static var whitespaceNSColour: NSColor {
        .quaternaryLabelColor
    }

    /// The SwiftUI form of the whitespace tone.
    public static var whitespaceColour: Color {
        Color(nsColor: whitespaceNSColour)
    }
}
