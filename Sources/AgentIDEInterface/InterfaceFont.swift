import SwiftUI

// MARK: - InterfaceFont

/// Applies the platform's interface typography.
private struct InterfaceFont: ViewModifier {
    // MARK: Internal

    let style: Font.TextStyle
    let weight: Font.Weight?
    let monospaced: Bool

    func body(content: Content) -> some View {
        content.font(interfaceStyle.font(style, weight: weight, monospaced: monospaced))
    }

    // MARK: Private

    private var interfaceStyle: InterfaceStyle = .init()
}

public extension View {
    /// Draws text in the platform's interface typography.
    func interfaceFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        monospaced: Bool = false,
    ) -> some View {
        modifier(InterfaceFont(style: style, weight: weight, monospaced: monospaced))
    }
}
