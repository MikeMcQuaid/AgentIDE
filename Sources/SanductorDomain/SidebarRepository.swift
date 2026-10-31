/// The Mac sidebar's order and public owner identity, shared with the phone.
public struct SidebarRepository: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Captures a repository and its ordered worktree paths.
    public init(
        name: String,
        owner: String?,
        worktrees: [String],
        entries: [SidebarEntry] = [],
        lastActivityAt: Int = 0,
        fullName: String? = nil,
        defaultBranch: String? = nil,
        isHidden: Bool = false,
    ) {
        self.name = name
        self.owner = owner
        self.worktrees = worktrees
        self.entries = entries
        self.lastActivityAt = lastActivityAt
        self.fullName = fullName ?? owner.map { $0 + "/" + name } ?? name
        self.defaultBranch = defaultBranch
        self.isHidden = isHidden
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            owner: container.decodeIfPresent(String.self, forKey: .owner),
            worktrees: container.decode([String].self, forKey: .worktrees),
            entries: container.decodeIfPresent([SidebarEntry].self, forKey: .entries) ?? [],
            lastActivityAt: container.decodeIfPresent(Int.self, forKey: .lastActivityAt) ?? 0,
            fullName: container.decodeIfPresent(String.self, forKey: .fullName),
            defaultBranch: container.decodeIfPresent(String.self, forKey: .defaultBranch),
            isHidden: container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false,
        )
    }

    // MARK: Public

    /// The checkout's directory name.
    public let name: String
    /// The public GitHub owner, when known.
    public let owner: String?
    /// Worktree paths in sidebar order, including the main checkout.
    public let worktrees: [String]
    /// Empty in snapshots written by older Mac builds.
    public let entries: [SidebarEntry]
    /// Recorded worktree activity for the phone's repository ordering.
    public let lastActivityAt: Int

    /// The GitHub name when known, retaining the checkout name separately for navigation.
    public let fullName: String

    /// The recorded default branch, absent from older snapshots or when unknown.
    public let defaultBranch: String?
    /// Visibility last published by the Mac, with no schedule needed on the phone.
    public let isHidden: Bool
}
