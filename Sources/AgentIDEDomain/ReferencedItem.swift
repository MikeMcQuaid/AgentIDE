// MARK: - ReferencedItem

/// Something GitHub refers to by a short label within a repository,
/// `#123` for an issue or a pull request, a GHSA id for a security
/// advisory or a branch's own name, as its pickers show and search it.
public protocol ReferencedItem: Identifiable {
    /// Whether the label is a name git owns, such as a branch.
    static var isGitName: Bool { get }

    /// The label GitHub refers to it by.
    var reference: String { get }

    /// Its title.
    var title: String { get }
}

public extension ReferencedItem {
    /// Labels are GitHub's unless a type says otherwise.
    static var isGitName: Bool {
        false
    }
}
