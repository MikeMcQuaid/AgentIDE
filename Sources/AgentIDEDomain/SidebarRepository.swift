/// The Mac sidebar's order and public owner identity, shared with the phone.
public struct SidebarRepository: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Captures a repository and its ordered worktree paths.
    public init(name: String, owner: String?, worktrees: [String]) {
        self.name = name
        self.owner = owner
        self.worktrees = worktrees
    }

    // MARK: Public

    /// The checkout's directory name.
    public let name: String
    /// The public GitHub owner, when known.
    public let owner: String?
    /// Worktree paths in sidebar order, including the main checkout.
    public let worktrees: [String]
}
