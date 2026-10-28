// MARK: - SidebarRequest

/// The only sidebar operations the phone may ask the host to perform.
public enum SidebarRequest: Codable, Sendable {
    case refreshStatus
    case sources(repositoryPath: String)
    case save(WorkBlock)
    case remove(WorkBlock)

    // MARK: Public

    public static let maximumBytes = 16_384
}

// MARK: - SidebarResponse

/// A picker listing or an acknowledged edit; an error never confirms a save.
public struct SidebarResponse: Codable, Sendable {
    // MARK: Lifecycle

    public init(issues: [IssueSummary] = [], pullRequests: [PullRequestSummary] = [], error: String? = nil) {
        self.issues = issues
        self.pullRequests = pullRequests
        self.error = error
    }

    // MARK: Public

    public let issues: [IssueSummary]
    public let pullRequests: [PullRequestSummary]
    public let error: String?
}
