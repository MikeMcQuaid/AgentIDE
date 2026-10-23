import AgentIDEDomain

extension PullRequestStore {
    // Nil distinguishes a fresh cached listing from a fetched empty one.
    // swiftlint:disable:next discouraged_optional_collection
    static let listingReads: PullRequestReads<[PullRequestSummary]?> = .init()
    static let summaryReads: PullRequestReads<PullRequestSummary?> = .init()
    static let conversationReads: PullRequestReads<PullRequestConversation> = .init()
}

// MARK: - PullRequestReads

/// Shares an in-flight answer across store instances for one metadata file.
actor PullRequestReads<Value: Sendable> {
    // MARK: Internal

    func run(key: [String], read: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let running = pending[key] {
            return try await running.value
        }
        let task = Task {
            try await read()
        }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }

    // MARK: Private

    private var pending: [[String]: Task<Value, any Error>] = [:]
}
