import Foundation

/// The shapes `gh pr list` and `gh pr view` JSON decode into. Split
/// from the client body for length.
extension GitHubClient {
    struct AutoMergeRow: Decodable {
        // Presence is the signal.
    }

    struct RowAuthor: Decodable {
        let login: String?
    }

    struct PullRequestRow: Decodable {
        let number: Int
        let title: String
        let url: String
        let headRefName: String
        let headRefOid: String?
        let baseRefName: String?
        let state: String?
        let mergeable: String?
        let reviewDecision: String?
        let author: RowAuthor?
        let body: String?
        // Optional because older gh versions omit the field.
        // swiftlint:disable:next discouraged_optional_boolean
        let isDraft: Bool?
        let autoMergeRequest: AutoMergeRow?
        let closedAt: Date?
        // Absent from the JSON when a pull request has no checks.
        // swiftlint:disable:next discouraged_optional_collection
        let statusCheckRollup: [CheckRow]?
        // Absent from older gh versions' JSON.
        // swiftlint:disable:next discouraged_optional_collection
        let reviewRequests: [ReviewRequestRow]?
        // swiftlint:disable:next discouraged_optional_collection
        let latestReviews: [ReviewRow]?
    }

    struct ReviewRequestRow: Decodable {
        let login: String?
    }

    struct ReviewRow: Decodable {
        let author: RowAuthor?
        let submittedAt: Date?
    }

    struct CheckRow: Decodable {
        let state: String?
        let conclusion: String?
        // The property must match gh's JSON key exactly.
        // swiftformat:disable:next acronyms
        let detailsUrl: String?
    }
}
