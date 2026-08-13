import AppKit
import SwiftUI

/// The one code typography shared by every surface that renders
/// code: terminals, diffs, the editor and finder results.
/// Nonisolated because AppKit layout machinery reads it outside the
/// main actor's checking.
public nonisolated enum CodeStyle {
    /// The shared monospaced point size.
    public static let pointSize: CGFloat = 13

    /// The AppKit font for text views and terminals: SF Mono when
    /// available, the system monospaced face otherwise.
    public static var nsFont: NSFont {
        NSFont(name: "SFMono-Regular", size: pointSize)
            ?? .monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }

    /// The SwiftUI font for diff lines and result rows, from the
    /// same AppKit face.
    public static var font: Font {
        Font(nsFont)
    }

    /// The light tone shared by visible whitespace glyphs in the
    /// diff and the editor.
    public static var whitespaceNSColour: NSColor {
        .quaternaryLabelColor
    }
}
