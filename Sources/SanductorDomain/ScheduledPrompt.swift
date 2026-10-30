import Foundation

/// A repository's recurring task and the last launch's outcome.
public struct ScheduledPrompt: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(repositoryPath: String) {
        self.repositoryPath = repositoryPath
    }

    // MARK: Public

    public var id: UUID = .init()
    public var repositoryPath: String
    public var name = ""
    public var prompt = ""
    public var agent: AgentKind = .claudeCode
    public var model = ""
    public var effort = ""
    public var schedule: PromptSchedule = .init()
    public var isEnabled = true
    public var nextRun: Date?
    public var lastRun: Date?
    public var lastSession: String?
    public var lastError: String?

    public var isValid: Bool {
        repositoryPath.isEmpty == false
            && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Stable across a launch retry, distinct across schedules and occurrences.
    public func branch(for date: Date) -> String {
        "scheduled_" + SessionName.slug(String(name.prefix(Self.nameLimit))) + "_"
            + date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + "_"
            + String(Int(date.timeIntervalSince1970)) + "_" + id.uuidString.prefix(Self.idLength).lowercased()
    }

    // MARK: Private

    private static let nameLimit = 40
    private static let idLength = 8
}
