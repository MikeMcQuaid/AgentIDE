import Foundation
import Synchronization

// MARK: - InFlightFetches

/// The fetches running now, one per repository, so a launch, a
/// rebase and a push that each find the remotes stale share one
/// `git fetch` rather than racing on the same refs. A finished fetch
/// leaves at once; a later ask decides afresh.
final class InFlightFetches: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up: tasks remove themselves.
    }

    // MARK: Internal

    let running: Mutex<[String: Task<Void, any Error>]> = .init([:])
}

// MARK: - Fetching

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

        let (fetch, isJoined) = inFlightFetches.running.withLock { running -> (Task<Void, any Error>, Bool) in
            if let joined = running[repositoryPath] {
                return (joined, true)
            }

            let fetch = Task {
                defer { inFlightFetches.running.withLock { $0[repositoryPath] = nil } }
                try await git.fetch(repositoryPath: workingDirectory ?? repositoryPath)
                rememberFetch(repositoryPath: repositoryPath)
            }
            running[repositoryPath] = fetch
            return (fetch, false)
        }
        await progress(
            isJoined ? "Waiting for the fetch already running in this repository" : "Fetching repository remotes",
        )
        try await fetch.value
    }

    /// Records that a repository's remotes are current, for the
    /// fetches that always run: the explicit ones a menu asks for.
    func rememberFetch(repositoryPath: String) {
        store.update { $0.gitFetchedAt[repositoryPath] = Date() }
    }
}
