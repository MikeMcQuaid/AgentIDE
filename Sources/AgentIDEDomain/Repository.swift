/// A git repository in the shared workspace.
public struct Repository: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a repository from its checkout location.
    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    // MARK: Public

    /// The repository's directory name.
    public let name: String

    /// The absolute path of the checkout.
    public let path: String

    /// The stable identity, the checkout path.
    public var id: String {
        path
    }
}
