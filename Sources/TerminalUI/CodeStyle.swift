import AppKit
import SwiftUI

/// The one code typography shared by every surface that renders
/// code: terminals, diffs, the editor and finder results.
/// Nonisolated because AppKit layout machinery reads it outside the
/// main actor's checking.
public nonisolated enum CodeStyle {
    /// The default face; Settings can change it.
    public static let defaultFontName = "SFMono-Regular"

    /// The default point size; Settings can change it.
    public static let defaultPointSize: CGFloat = 13

    /// The shared monospaced point size, as Settings left it.
    public static var pointSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "codeFontSize")
        return stored > 0 ? stored : defaultPointSize
    }

    /// The AppKit font for text views and terminals: the face
    /// Settings chose, SF Mono until then, the system monospaced
    /// face when neither loads. Existing terminals keep the font
    /// they opened with; everything else follows on its next render.
    public static var nsFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "codeFontName") ?? defaultFontName
        return NSFont(name: name, size: pointSize)
            ?? NSFont(name: defaultFontName, size: pointSize)
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

    /// The SwiftUI tint marking whitespace in diff lines: a
    /// background rather than substitute glyphs, so copied diff
    /// text stays character-exact.
    public static var whitespaceColour: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
}
