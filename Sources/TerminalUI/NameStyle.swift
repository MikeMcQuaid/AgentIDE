import AgentIDEData
import AppKit
import SwiftUI

/// The shared, live typography for names git owns. Code has its
/// own preferences through `CodeStyle`.
public struct NameStyle: DynamicProperty {
    // MARK: Lifecycle

    /// Observes the font preferences used by this view.
    public init() {
        // AppStorage supplies the saved values or their original defaults.
    }

    // MARK: Public

    /// The original system callout size.
    public static let defaultPointSize = NSFont.preferredFont(forTextStyle: .callout).pointSize

    /// A name in a row of its own: a sidebar row or a popover's list.
    public var font: Font {
        resolved(style: .callout, pointSize: Self.defaultPointSize)
    }

    /// A name in a detail line, beside counts and badges.
    public var small: Font {
        resolved(style: .caption, pointSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)
    }

    /// A name in AppKit text, at the size of `font`.
    public var appKitFont: NSFont {
        let size = max(Self.defaultPointSize + delta, 1)
        return (fontName.isEmpty ? nil : NSFont(name: fontName, size: size))
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: Private

    @AppStorage(AppSettings.nameFontNameKey)
    private var fontName = ""
    @AppStorage(AppSettings.nameFontSizeKey)
    private var fontSize = 0.0

    private var delta: CGFloat {
        if fontSize > 0 {
            fontSize - Self.defaultPointSize
        } else {
            0
        }
    }

    private func resolved(style: Font.TextStyle, pointSize: CGFloat) -> Font {
        let size = max(pointSize + delta, 1)
        if fontName.isEmpty == false, let face = NSFont(name: fontName, size: size) {
            return Font(face)
        }
        if delta == 0 {
            return .system(style, design: .monospaced)
        }
        return .system(size: size, design: .monospaced)
    }
}
