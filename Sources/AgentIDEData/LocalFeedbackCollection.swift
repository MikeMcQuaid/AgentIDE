import AgentIDEDomain

// MARK: - LocalFeedbackCollection

/// Captured local evidence is valid only for the exact code and selected reviewer.
public struct LocalFeedbackCollection: Codable, Equatable, Sendable {
    public let id: String
    public let revision: String
    public let configuration: String
    public var isPending = true
    public var review: LocalReview?
    public var failure: String?
}

// MARK: - FeedbackCollector

/// Local reviews run beside the existing refresh, never inside its critical path.
actor FeedbackCollector {
    // MARK: Internal

    func isRunning(_ key: String) -> Bool {
        tasks[key] != nil
    }

    func start(_ key: String, operation: @escaping @Sendable () async -> Void) {
        guard tasks[key] == nil else {
            return
        }

        tasks[key] = Task {
            await operation()
            tasks[key] = nil
        }
    }

    func wait(_ key: String) async {
        await tasks[key]?.value
    }

    // MARK: Private

    private var tasks: [String: Task<Void, Never>] = [:]
}
