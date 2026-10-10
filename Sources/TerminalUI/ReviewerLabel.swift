import AgentIDEDomain
import SwiftUI

/// The same brand mark and name in local and remote reviewer menus.
public struct ReviewerLabel: View {
    // MARK: Lifecycle

    public init(_ agent: AgentKind) {
        title = agent.displayName
        image = agent.iconAssetName
    }

    public init(_ bot: ReviewBot) {
        title = bot.displayName
        image = bot.iconAssetName
    }

    // MARK: Public

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
        }
    }

    // MARK: Private

    private static let iconSize: CGFloat = 14

    private let title: String
    private let image: String
}
