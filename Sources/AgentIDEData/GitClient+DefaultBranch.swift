import AgentIDEDomain

/// Following a default branch that moved on the remote. Split from
/// the client body for length.
public extension GitClient {
    /// A default branch that moved: the branch it was and the one
    /// it is now.
    struct DefaultBranchMove: Equatable, Sendable {
        // MARK: Lifecycle

        public init(previous: String, current: String) {
            self.previous = previous
            self.current = current
        }

        // MARK: Public

        public let previous: String
        public let current: String
    }

    /// Where origin's HEAD points now, then what the default branch
    /// is read from. `origin/HEAD` is set once at clone time and a
    /// fetch never moves it, so a repository whose default branch
    /// went from `trunk` to `main` on GitHub kept reading as `trunk`
    /// here; only an explicit fetch pays for this extra round trip.
    /// When the default branch has moved, a main checkout sitting
    /// on the old one is checked out on the new, made from origin's
    /// if there is no local one, and the move is returned. Origin is
    /// fetched first, so the branch its HEAD now names has a tracking
    /// ref here to be checked out from; a remote that will not say
    /// where its HEAD points is left as it was, since the fetch that
    /// was asked for has already happened.
    func followDefaultBranch(of repository: Repository) async throws -> DefaultBranchMove? {
        let before = await defaultBaseRef(of: repository).map { Self.branchName(of: $0) }
        try await git(["fetch", "origin"], in: repository.path)
        let asked = try await git(["remote", "set-head", "origin", "--auto"], in: repository.path, allowFailure: true)
        guard asked.succeeded else {
            return nil
        }

        await RepositoryFacts.shared.forget(repository.path)
        let after = await defaultBaseRef(of: repository).map { Self.branchName(of: $0) }
        guard let before, let after, before != after else {
            return nil
        }

        let move = DefaultBranchMove(previous: before, current: after)
        if await currentBranch(worktreePath: repository.path) == move.previous {
            try await checkout(branch: move.current, worktreePath: repository.path)
        }
        return move
    }

    /// A base ref's branch: `origin/main` is `main`.
    private static func branchName(of baseRef: String) -> String {
        if baseRef.hasPrefix("origin/") {
            String(baseRef.dropFirst("origin/".count))
        } else {
            baseRef
        }
    }
}
