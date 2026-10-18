#if os(iOS)
    import SwiftUI

    /// Names git owns use the system monospaced callout style.
    public typealias NameStyle = MobileNameStyle

    public struct MobileNameStyle: DynamicProperty {
        // MARK: Lifecycle

        public init() {
            // System fonts need no configuration.
        }

        // MARK: Public

        public var font: Font {
            .system(.callout, design: .monospaced)
        }
    }
#endif
