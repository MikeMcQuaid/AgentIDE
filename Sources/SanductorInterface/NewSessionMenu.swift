import SanductorDomain
import SwiftUI

/// Repository choices grouped by owner, sharing the sidebar's avatar cache.
public struct NewSessionMenu: View {
    // MARK: Lifecycle

    public init(repositories: [Repository], select: @escaping (Repository) -> Void) {
        self.repositories = repositories
        self.select = select
    }

    // MARK: Public

    public var body: some View {
        let grouped = Dictionary(grouping: repositories) { $0.owner?.lowercased() ?? "" }
        Menu("New session", systemImage: "plus") {
            ForEach(grouped.keys.sorted(), id: \.self) { owner in
                Section {
                    ForEach(grouped[owner, default: []].sorted { first, second in
                        first.name.localizedStandardCompare(second.name) == .orderedAscending
                    }) { repository in
                        Button { select(repository) } label: {
                            Label {
                                Text(repository.name)
                            } icon: {
                                if let image = avatars.images[owner] {
                                    Image(decorative: image, scale: CGFloat(image.width) / Self.avatarSize)
                                        .renderingMode(.original)
                                } else {
                                    Image(systemName: "folder.fill")
                                }
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel(repository.fullName ?? repository.name)
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.primary)
        .menuOrder(.fixed)
        // Native menu labels need an Image ready before the menu opens.
        .task(id: grouped.keys.sorted()) {
            for owner in grouped.keys where owner.isEmpty == false {
                avatars.load(owner)
            }
        }
    }

    // MARK: Private

    private static let avatarSize: CGFloat = 16

    private let repositories: [Repository]
    private let select: (Repository) -> Void
    private var avatars: OwnerAvatarStore = .shared
}
