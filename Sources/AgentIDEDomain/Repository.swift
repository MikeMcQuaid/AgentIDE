/// A git repository in the shared workspace.
public struct Repository: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a repository from its checkout location.
    public init(name: String, path: String, fullName: String? = nil) {
        self.name = name
        self.path = path
        self.fullName = fullName
    }

    // MARK: Public

    /// The repository's directory name.
    public let name: String

    /// The absolute path of the checkout.
    public let path: String

    /// The GitHub `owner/name`, when the origin remote points there.
    public let fullName: String?

    /// The GitHub account that owns the repository, for its avatar.
    public var owner: String? {
        fullName?.split(separator: "/").first.map(String.init)
    }

    /// The stable identity, the checkout path.
    public var id: String {
        path
    }
}
