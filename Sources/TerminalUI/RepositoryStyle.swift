import AgentIDEData
import AppKit
import SwiftUI

/// The sidebar's repository names, retaining their original weight.
public struct RepositoryStyle: DynamicProperty {
    // MARK: Lifecycle

    /// Observes the font preferences used by this view.
    public init() {
        // AppStorage supplies the saved values or their original defaults.
    }

    // MARK: Public

    /// The original system subheadline size.
    public static let defaultPointSize = NSFont.preferredFont(forTextStyle: .subheadline).pointSize

    /// The repository header and new-repository label.
    public var font: Font {
        let size = fontSize > 0 ? fontSize : Self.defaultPointSize
        if fontName.isEmpty == false, let face = NSFont(name: fontName, size: size) {
            return Font(face).weight(.semibold)
        }
        return (size == Self.defaultPointSize ? Font.subheadline : .system(size: size)).weight(.semibold)
    }

    // MARK: Private

    @AppStorage(AppSettings.repositoryFontNameKey)
    private var fontName = ""
    @AppStorage(AppSettings.repositoryFontSizeKey)
    private var fontSize = 0.0
}
