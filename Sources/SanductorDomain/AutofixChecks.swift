// MARK: - AutofixCheck

/// Evidence from one check on the PR's head, separate from the display rollup.
public struct AutofixCheck: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(name: String, status: String, conclusion: String, runID: String, link: String) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.runID = runID
        self.link = link
    }

    // MARK: Public

    public let name: String
    public let status: String
    public let conclusion: String
    public let runID: String
    public let link: String

    public var isFailure: Bool {
        ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE"].contains(conclusion)
    }
}

// MARK: - AutofixChecks

/// Missing required results block automation even when the rollup is already red.
public struct AutofixChecks: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(required: Set<String>, results: [AutofixCheck]) {
        self.required = required
        self.results = results.filter { required.contains($0.name) }
    }

    // MARK: Public

    public let required: Set<String>
    public let results: [AutofixCheck]

    public var isComplete: Bool {
        required.isSubset(of: Set(results.map(\.name)))
            && results.allSatisfy { $0.status == "COMPLETED" && $0.conclusion.isEmpty == false }
    }

    public var failures: [AutofixCheck] {
        guard required.isEmpty == false, isComplete else {
            return []
        }

        return results.filter(\.isFailure)
    }
}
