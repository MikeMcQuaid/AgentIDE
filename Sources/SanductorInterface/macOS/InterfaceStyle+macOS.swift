#if os(macOS)
    import AppKit
    import SanductorDomain
    import SwiftUI

    // MARK: - InterfaceStyle

    // The typography for everything that is neither code nor a name
    // git owns: labels, headings, captions and prose. The system font
    // until Fonts settings changes it, every text style moving by the
    // points body text moved so the hierarchy between them holds.
    // SwiftUI's dynamic type sizes change nothing on macOS, so views
    // ask for a style through `interfaceFont(_:weight:monospaced:)`.

    public struct InterfaceStyle: DynamicProperty {
        // MARK: Lifecycle

        /// Observes the font preferences used by this view.
        public init() {
            // AppStorage supplies the saved values or their original defaults.
        }

        // MARK: Public

        /// The original system body size.
        public static let defaultPointSize = NSFont.preferredFont(forTextStyle: .body).pointSize

        /// A text style as Settings left it, drawn exactly as the bare
        /// style until anything changes. Monospaced text keeps the
        /// system monospaced face whatever face was chosen, since what
        /// it draws depends on its columns.
        public func font(_ style: Font.TextStyle, weight: Font.Weight? = nil, monospaced: Bool = false) -> Font {
            let preferred = NSFont.preferredFont(forTextStyle: Self.appKitStyles[style] ?? .body)
            let size = preferred.pointSize + delta
            // The system applies a style's own weight, such as the
            // headline's bold; a size or a chosen face has to ask for it.
            let natural: Font.Weight? = preferred.fontDescriptor.symbolicTraits.contains(.bold) ? .bold : nil
            if monospaced == false, let face = customFace(size: size) {
                return (weight ?? natural).map { Font(face).weight($0) } ?? Font(face)
            }
            var font: Font = delta == 0 ? .system(style) : .system(size: max(size, 1), weight: natural)
            if monospaced {
                font = font.monospaced()
            }
            return weight.map { font.weight($0) } ?? font
        }

        /// The same text style for AppKit text, the system's own font
        /// for it until anything changes.
        public func appKitFont(_ style: NSFont.TextStyle, bold: Bool = false, monospaced: Bool = false) -> NSFont {
            let preferred = NSFont.preferredFont(forTextStyle: style)
            let size = max(preferred.pointSize + delta, 1)
            let isBold = bold || preferred.fontDescriptor.symbolicTraits.contains(.bold)
            if monospaced {
                return .monospacedSystemFont(ofSize: size, weight: isBold ? .bold : .regular)
            }
            if let face = customFace(size: size) {
                return isBold ? NSFontManager.shared.convert(face, toHaveTrait: .boldFontMask) : face
            }
            if bold {
                return .boldSystemFont(ofSize: size)
            }
            return delta == 0 ? preferred : .systemFont(ofSize: size, weight: isBold ? .bold : .regular)
        }

        /// A size fixed in the original design, such as a symbol drawn
        /// beside text, moved with the text around it.
        public func systemFont(ofSize size: CGFloat) -> Font {
            .system(size: max(size + delta, 1))
        }

        // MARK: Private

        /// AppKit's name for each SwiftUI text style; body for any other.
        private static let appKitStyles: [Font.TextStyle: NSFont.TextStyle] = [
            .largeTitle: .largeTitle,
            .title: .title1,
            .title2: .title2,
            .title3: .title3,
            .headline: .headline,
            .subheadline: .subheadline,
            .callout: .callout,
            .footnote: .footnote,
            .caption: .caption1,
            .caption2: .caption2,
        ]

        @AppStorage(FontPreferences.interfaceFontNameKey)
        private var fontName = ""
        @AppStorage(FontPreferences.interfaceFontSizeKey)
        private var fontSize = 0.0

        private var delta: CGFloat {
            if fontSize > 0 {
                max(fontSize, 1) - Self.defaultPointSize
            } else {
                0
            }
        }

        private func customFace(size: CGFloat) -> NSFont? {
            if fontName.isEmpty {
                nil
            } else {
                NSFont(name: fontName, size: max(size, 1))
            }
        }
    }
#endif
