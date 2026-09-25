import Foundation

extension GitClient {
    func withRemoteOperation<Value: Sendable>(
        worktreePath: String,
        operation: @Sendable () async throws -> Value,
    ) async throws -> Value {
        let directory = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try await RemoteOperations.shared.run(
            repository: URL(fileURLWithPath: directory).resolvingSymlinksInPath().path,
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
        operation: @Sendable () async throws -> Value,
    ) async throws -> Value {
        // Actor isolation alone releases at every await; the queue
        // keeps the whole operation exclusive for this repository.
        if waiters[repository] != nil {
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
