/// Which repositories a sidebar reading asks git about: all of them,
/// or only the ones due, the rest keeping their last rows. A
/// repository nothing is happening in changes on no tick, and
/// asking it anyway was most of everything the app did.
public enum GitReadScope: Sendable {
    case all
    case only(Set<String>)

    // MARK: Public

    /// Whether a repository's git is read under this scope.
    public func includes(_ repositoryPath: String) -> Bool {
        switch self {
        case .all:
            true

        case let .only(paths):
            paths.contains(repositoryPath)
        }
    }
}
