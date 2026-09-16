import AgentIDEData
import AppKit
import SwiftUI

/// The one code typography shared by every surface that renders
/// code: terminals, diffs, the editor and finder results.
/// Views observe preferences; AppKit layout can also read the
/// current font directly without owning a SwiftUI property.
public struct CodeStyle: DynamicProperty {
    // MARK: Lifecycle

    /// Observes the font preferences used by this view.
    public init() {
        // AppStorage supplies the saved values or their original defaults.
    }

    // MARK: Public

    /// The default face; Settings can change it.
    public nonisolated static let defaultFontName = "SFMono-Regular"

    /// The default point size; Settings can change it.
    public nonisolated static let defaultPointSize: CGFloat = 13

    /// The shared monospaced point size, as Settings left it.
    public nonisolated static var pointSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: AppSettings.codeFontSizeKey)
        return stored > 0 ? stored : defaultPointSize
    }

    /// The AppKit font for text views and terminals: the face
    /// Settings chose, SF Mono until then, the system monospaced
    /// face when neither loads.
    public nonisolated static var nsFont: NSFont {
        resolve(
            name: UserDefaults.standard.string(forKey: AppSettings.codeFontNameKey) ?? defaultFontName,
            size: pointSize,
        )
    }

    /// The light tone shared by visible whitespace glyphs in the
    /// diff and the editor.
    public nonisolated static var whitespaceNSColour: NSColor {
        .quaternaryLabelColor
    }

    /// The SwiftUI tint marking whitespace in diff lines: a
    /// background rather than substitute glyphs, so copied diff
    /// text stays character-exact.
    public nonisolated static var whitespaceColour: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    /// Observed by mounted editors and terminals so changes apply live.
    public var appKitFont: NSFont {
        Self.resolve(name: fontName, size: fontSize)
    }

    /// The SwiftUI font for diff lines and result rows, from the
    /// same AppKit face.
    public var font: Font {
        Font(appKitFont)
    }

    // MARK: Private

    @AppStorage(AppSettings.codeFontNameKey)
    private var fontName = "SFMono-Regular"
    @AppStorage(AppSettings.codeFontSizeKey)
    private var fontSize = 13.0

    private nonisolated static func resolve(name: String, size: CGFloat) -> NSFont {
        let resolvedSize = size > 0 ? size : defaultPointSize
        return NSFont(name: name, size: resolvedSize)
            ?? NSFont(name: defaultFontName, size: resolvedSize)
            ?? .monospacedSystemFont(ofSize: resolvedSize, weight: .regular)
    }
}
