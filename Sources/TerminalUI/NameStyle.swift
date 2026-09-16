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
        resolved(style: .callout, pointSize: Self.defaultPointSize, monospaced: true)
    }

    /// A name in a detail line, beside counts and badges.
    public var small: Font {
        resolved(style: .caption, pointSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, monospaced: true)
    }

    /// Sidebar counts and status text scale with the names they describe.
    public var detail: Font {
        resolved(style: .caption, pointSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, monospaced: false)
    }

    // MARK: Private

    @AppStorage(AppSettings.nameFontNameKey)
    private var fontName = ""
    @AppStorage(AppSettings.nameFontSizeKey)
    private var fontSize = 0.0

    private func resolved(style: Font.TextStyle, pointSize: CGFloat, monospaced: Bool) -> Font {
        let delta = fontSize > 0 ? fontSize - Self.defaultPointSize : 0
        let size = max(pointSize + delta, 1)
        if fontName.isEmpty == false, let face = NSFont(name: fontName, size: size) {
            return Font(face)
        }
        let design: Font.Design = monospaced ? .monospaced : .default
        if delta == 0 {
            return monospaced ? .system(style, design: .monospaced) : .system(style)
        }
        return .system(size: size, design: design)
    }
}
