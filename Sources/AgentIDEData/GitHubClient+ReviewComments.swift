import AgentIDEDomain
import Foundation

public extension GitHubClient {
    /// The shared timeline reader retains GitHub IDs, account types and reviewed heads.
    func reviewComments(repositoryPath: String, number: Int) async throws -> [ReviewComment] {
        async let reviews = gh(
            ["api", "repos/{owner}/{repo}/pulls/" + String(number) + "/reviews?per_page=100", "--paginate", "--slurp"],
            in: repositoryPath,
        )
        async let comments = gh(
            [
                "api",
                "repos/{owner}/{repo}/issues/" + String(number) + "/comments?per_page=100",
                "--paginate",
                "--slurp",
            ],
            in: repositoryPath,
        )
        return try await Self.reviewComments(fromJSON: reviews.standardOutput)
            + Self.reviewComments(fromJSON: comments.standardOutput)
    }

    internal static func reviewComments(fromJSON json: String) throws -> [ReviewComment] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([[ReviewCommentRow]].self, from: Data(json.utf8)).flatMap { page in
            page.compactMap { row in
                let body = row.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let kind = row.state ?? ""
                let botReview = kind == "COMMENTED" && row.user?.type == "Bot"
                    && ReviewBot.allCases.contains { $0.matches(row.user?.login) }
                guard body.isEmpty == false || (kind.isEmpty == false && kind != "COMMENTED") || botReview else {
                    return nil
                }

                return ReviewComment(
                    id: kind.isEmpty ? -row.id : row.id,
                    author: row.user?.login ?? "unknown",
                    body: body,
                    kind: kind,
                    nodeID: row.nodeID,
                    authorType: row.user?.type,
                    commit: row.commitID,
                    date: row.submittedAt ?? row.updatedAt,
                )
            }
        }
    }
}

// MARK: - ReviewCommentRow

private struct ReviewCommentRow: Decodable {
    // MARK: Internal

    struct User: Decodable {
        let login: String
        let type: String
    }

    let id: Int
    let nodeID: String?
    let user: User?
    let body: String?
    let state: String?
    let commitID: String?
    let submittedAt: Date?
    let updatedAt: Date?

    // MARK: Private

    // REST field names are fixed by GitHub.
    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case state
        case nodeID = "node_id"
        case commitID = "commit_id"
        case submittedAt = "submitted_at"
        case updatedAt = "updated_at"
    }
    // swiftlint:enable explicit_enum_raw_value
}
