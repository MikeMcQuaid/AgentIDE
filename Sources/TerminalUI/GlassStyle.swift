import SwiftUI

public extension View {
    /// Liquid Glass when the OS has it; bordered glass otherwise, so
    /// one binary on macOS 15 through 27 keeps the Tahoe look where
    /// it exists and a HIG-compatible fallback where it does not.
    func agentGlassButtonStyle() -> some View {
        modifier(AgentGlassButtonModifier(prominent: false))
    }

    /// Prominent Liquid Glass when available; bordered prominent
    /// otherwise.
    func agentGlassProminentButtonStyle() -> some View {
        modifier(AgentGlassButtonModifier(prominent: true))
    }
}

// MARK: - AgentGlassButtonModifier

/// Applies `.glass` / `.glassProminent` on macOS 26+, else bordered
/// styles that match the same primary-versus-secondary roles.
private struct AgentGlassButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
