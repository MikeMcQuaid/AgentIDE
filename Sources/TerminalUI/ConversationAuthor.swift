import SanductorDomain
import SwiftUI

/// Selectable author names with the same review bot branding on every surface.
public struct ConversationAuthor: View {
    // MARK: Lifecycle

    public init(_ login: String, showsAvatar: Bool = true) {
        self.login = login
        self.showsAvatar = showsAvatar
    }

    // MARK: Public

    public var body: some View {
        HStack(spacing: Self.spacing) {
            if let bot = ReviewBot.allCases.first(where: { $0.matches(login) }) {
                Image(bot.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
            } else if showsAvatar {
                OwnerAvatar(owner: login, size: Self.iconSize, placeholder: "person.crop.circle.fill")
                    .clipShape(Circle())
            }
            MarkdownText(ChecksStyle.authorDisplayName(login))
                .fontWeight(.semibold)
        }
        .fixedSize()
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let iconSize: CGFloat = 14

    private let login: String
    private let showsAvatar: Bool
}
