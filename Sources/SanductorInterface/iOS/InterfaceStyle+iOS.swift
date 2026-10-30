#if os(iOS)
    import SwiftUI

    /// Interface typography follows the system text styles and Dynamic Type.
    typealias InterfaceStyle = MobileInterfaceStyle

    struct MobileInterfaceStyle {
        func font(_ style: Font.TextStyle, weight: Font.Weight? = nil, monospaced: Bool = false) -> Font {
            var result = Font.system(style)
            if monospaced {
                result = result.monospaced()
            }
            return weight.map { result.weight($0) } ?? result
        }
    }
#endif
