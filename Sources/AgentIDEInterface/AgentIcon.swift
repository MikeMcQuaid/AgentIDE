import AgentIDEDomain
import SwiftUI

/// The same monochrome agent mark in desktop and phone session rows.
public struct AgentIcon: View {
    // MARK: Lifecycle

    public init(_ agent: AgentKind, size: CGFloat) {
        self.agent = agent
        self.size = size
    }

    // MARK: Public

    public var body: some View {
        Image(agent.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(agent.displayName)
    }

    // MARK: Private

    private let agent: AgentKind
    private let size: CGFloat
}
