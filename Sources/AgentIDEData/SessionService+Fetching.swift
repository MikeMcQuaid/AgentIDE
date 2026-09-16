import Foundation

/// When a repository's remotes were last fetched, and the one place
/// that decides whether to fetch again. Split from the sources for
/// length.
public extension SessionService {
    /// How long a fetch counts as current: a rebase started within
    /// the minute of one reuses it rather than waiting again.
    static let fetchInterval: TimeInterval = 60

    /// Fetches a repository's remotes unless they are fresh enough:
    /// rebases allow a minute, new worktrees an hour.
    func fetchIfStale(
        repositoryPath: String,
        workingDirectory: String? = nil,
        maxAge: TimeInterval = fetchInterval,
    ) async throws {
        let last = store.load().gitFetchedAt[repositoryPath] ?? .distantPast
        guard Date().timeIntervalSince(last) >= maxAge else {
            return
        }

        await progress("Fetching repository remotes")
        try await git.fetch(repositoryPath: workingDirectory ?? repositoryPath)
        rememberFetch(repositoryPath: repositoryPath)
    }

    /// Records that a repository's remotes are current, for the
    /// fetches that always run: the explicit ones a menu asks for.
    func rememberFetch(repositoryPath: String) {
        store.update { $0.gitFetchedAt[repositoryPath] = Date() }
    }
}
