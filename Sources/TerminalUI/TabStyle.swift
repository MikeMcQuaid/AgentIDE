import AgentIDEData
import AppKit
import SwiftUI

/// Utility tabs keep their system defaults until Fonts settings changes them.
public struct TabStyle: DynamicProperty {
    // MARK: Lifecycle

    /// Observes the font preferences used by this view.
    public init() {
        // AppStorage supplies the saved values or their original defaults.
    }

    // MARK: Public

    /// The original system callout size.
    public static let defaultPointSize = NSFont.preferredFont(forTextStyle: .callout).pointSize

    /// The tab label.
    public var font: Font {
        resolved(style: .callout, pointSize: Self.defaultPointSize)
    }

    /// A count follows the tab's size, retaining its smaller bold style.
    public var badge: Font {
        resolved(style: .caption, pointSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize).bold()
    }

    // MARK: Private

    @AppStorage(AppSettings.tabFontNameKey)
    private var fontName = ""
    @AppStorage(AppSettings.tabFontSizeKey)
    private var fontSize = 0.0

    private func resolved(style: Font.TextStyle, pointSize: CGFloat) -> Font {
        let delta = fontSize > 0 ? fontSize - Self.defaultPointSize : 0
        let size = max(pointSize + delta, 1)
        if fontName.isEmpty == false, let face = NSFont(name: fontName, size: size) {
            return Font(face)
        }
        return delta == 0 ? .system(style) : .system(size: size)
    }
}
