import Foundation

/// One reported check, or a required check that has not reported yet.
public struct PullRequestCheck: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        name: String,
        status: String,
        conclusion: String,
        requirement: Requirement,
        link: String = "",
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        workflowName: String? = nil,
        event: String? = nil,
    ) {
        self.name = name
        self.status = status.uppercased()
        self.conclusion = conclusion.uppercased()
        self.requirement = requirement
        self.link = link
        self.startedAt = startedAt.flatMap { $0 > .distantPast ? $0 : nil }
        self.completedAt = completedAt.flatMap { $0 > .distantPast ? $0 : nil }
        self.workflowName = workflowName
        self.event = event
    }

    // MARK: Public

    public enum Requirement: String, Codable, Sendable {
        case required = "Required"
        case optional = "Optional"
        case unknown = "Requirement unknown"
    }

    public let name: String
    public let status: String
    public let conclusion: String
    public let requirement: Requirement
    public let link: String
    public let startedAt: Date?
    public let completedAt: Date?
    public var workflowName: String?
    public var event: String?

    public var displayName: String {
        ((workflowName ?? "").isEmpty ? "" : (workflowName ?? "") + " / ")
            + name + ((event ?? "").isEmpty ? "" : " (" + (event ?? "") + ")")
    }

    public var id: String {
        name + ":" + link
    }

    public var isComplete: Bool {
        status == "COMPLETED"
    }

    public var statusDescription: String {
        switch status {
        case "EXPECTED":
            "Not yet reported"

        case "IN_PROGRESS":
            "Running"

        case "COMPLETED" where conclusion == "SUCCESS":
            "Successful"

        case "COMPLETED" where conclusion == "FAILURE":
            "Failed"

        case "COMPLETED":
            conclusion.isEmpty ? "Finished" : conclusion.replacing("_", with: " ").capitalized

        default:
            status.replacing("_", with: " ").capitalized
        }
    }

    /// Status contexts do not publish a start time, so their duration stays unknown.
    public var duration: TimeInterval? {
        guard isComplete, let startedAt, let completedAt, completedAt >= startedAt else {
            return nil
        }

        return completedAt.timeIntervalSince(startedAt)
    }

    public var jobID: Int? {
        guard let url = URL(string: link),
              url.pathComponents.contains("actions"),
              url.pathComponents.dropLast().last == "job",
              let number = Int(url.lastPathComponent), number > 0
        else {
            return nil
        }

        return number
    }

    public var hasNoLog: Bool {
        conclusion == "SKIPPED" || (conclusion == "CANCELLED" && startedAt == nil)
    }

    public var canReadLog: Bool {
        isComplete && jobID != nil && hasNoLog == false
    }
}
