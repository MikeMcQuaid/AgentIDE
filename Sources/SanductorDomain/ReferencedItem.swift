/// Something GitHub refers to by a short label within a repository,
/// `#123` for an issue or a pull request and a GHSA id for a security
/// advisory, as its pickers show and search it.
public protocol ReferencedItem: Identifiable {
    /// The label GitHub refers to it by.
    var reference: String { get }

    /// Its title.
    var title: String { get }
}
