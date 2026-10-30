import Foundation
import SanductorDomain

extension GitClient {
    /// Runs an operation alone among those for the same repository:
    /// remote operations, and every launch's branch naming and
    /// worktree creation, which write the same refs and config.
    /// `onWait` hears once when another holds the repository first.
    func withRemoteOperation<Value: Sendable>(
        worktreePath: String,
        onWait: LaunchReporter? = nil,
        operation: @Sendable () async throws -> Value,
    ) async throws -> Value {
        let directory = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try await RemoteOperations.shared.run(
            repository: URL(fileURLWithPath: directory).resolvingSymlinksInPath().path,
            onWait: onWait,
            operation: operation,
        )
    }
}

// MARK: - RemoteOperations

private actor RemoteOperations {
    // MARK: Internal

    static let shared: RemoteOperations = .init()

    func run<Value: Sendable>(
        repository: String,
        onWait: LaunchReporter?,
        operation: @Sendable () async throws -> Value,
    ) async throws -> Value {
        // Actor isolation alone releases at every await; the queue
        // keeps the whole operation exclusive for this repository.
        if let queued = waiters[repository] {
            // Not awaited: suspending here would let the holder finish
            // and drop the queue before this waiter joined it.
            if let onWait {
                let ahead = queued.count + 1
                Task {
                    await onWait(
                        ahead == 1
                            ? "Waiting for another launch or remote operation in this repository"
                            : "Waiting for " + String(ahead) + " earlier launches or remote operations"
                            + " in this repository",
                    )
                }
            }
            await withCheckedContinuation { waiters[repository, default: []].append($0) }
        } else {
            waiters[repository] = []
        }
        defer {
            if waiters[repository]?.isEmpty == false {
                waiters[repository]?.removeFirst().resume()
            } else {
                waiters[repository] = nil
            }
        }
        try Task.checkCancellation()
        return try await operation()
    }

    // MARK: Private

    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
}
