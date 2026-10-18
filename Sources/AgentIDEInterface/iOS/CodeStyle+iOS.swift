#if os(iOS)
    import SwiftUI
    import UIKit

    /// The terminal's adjustable monospaced size also follows Dynamic Type.
    public typealias CodeStyle = MobileCodeStyle

    public struct MobileCodeStyle: DynamicProperty {
        // MARK: Lifecycle

        public init() {
            // AppStorage supplies the base size; Dynamic Type scales it.
        }

        // MARK: Public

        public static let fontSizeKey = "phoneTerminalFontSize"
        public static let defaultPointSize = 13.0

        public var uiKitFont: UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .monospacedSystemFont(ofSize: fontSize > 0 ? fontSize : Self.defaultPointSize, weight: .regular),
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .init(dynamicTypeSize)),
            )
        }

        // MARK: Private

        @Environment(\.dynamicTypeSize)
        private var dynamicTypeSize
        @AppStorage(Self.fontSizeKey)
        private var fontSize: Double = Self.defaultPointSize
    }
#endif
