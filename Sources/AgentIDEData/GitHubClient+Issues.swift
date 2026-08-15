import AgentIDEDomain
import Foundation

// MARK: - PullRequestDetail

/// A pull request's prompt-relevant fields.
struct PullRequestDetail {
    let title: String
    let body: String
    let headBranch: String
}

// MARK: - Issues and reviews

/// Issue and pull request detail: prompt sources, checkouts and
/// review feedback.
public extension GitHubClient {
    /// The repository's open issues, newest first.
    func openIssues(repositoryPath: String) async -> [IssueSummary] {
        let result = try? await gh(
            ["issue", "list", "--state", "open", "--json", "number,title"],
            in: repositoryPath,
        )
        guard let output = result?.standardOutput,
              let rows = try? JSONDecoder().decode([IssueRow].self, from: Data(output.utf8))
        else {
            return []
        }

        return rows.map { IssueSummary(number: $0.number, title: $0.title) }
    }

    /// An issue's title and body, the seed of an agent prompt.
    func issue(repositoryPath: String, number: Int) async throws -> (title: String, body: String) {
        let result = try await gh(
            ["issue", "view", String(number), "--json", "title,body"],
            in: repositoryPath,
        )
        let decoded = try JSONDecoder().decode(TitledBody.self, from: Data(result.standardOutput.utf8))
        return (decoded.title, decoded.body ?? "")
    }

    /// A pull request's title, body and head branch.
    internal func pullRequestDetail(repositoryPath: String, number: Int) async throws -> PullRequestDetail {
        let result = try await gh(
            ["pr", "view", String(number), "--json", "title,body,headRefName"],
            in: repositoryPath,
        )
        let decoded = try JSONDecoder().decode(TitledBody.self, from: Data(result.standardOutput.utf8))
        return PullRequestDetail(
            title: decoded.title,
            body: decoded.body ?? "",
            headBranch: decoded.headRefName ?? "",
        )
    }

    /// Checks a pull request's branch out in a worktree so pushes and
    /// pulls track the pull request directly.
    func checkoutPullRequest(worktreePath: String, number: Int) async throws {
        try await gh(["pr", "checkout", String(number)], in: worktreePath)
    }

    /// Every human comment on a pull request: review bodies with
    /// their states, inline review comments and thread comments, in
    /// fetched order. Bodyless reviews stay when their state says
    /// something, so approvals appear in the timeline. Throws on
    /// fetch failure so callers keep their last good cache rather
    /// than mistaking a failure for no feedback.
    /// Review summaries and top-level comments only: inline file
    /// comments render as resolvable conversations with their
    /// `path:line` anchors instead, so the timeline never repeats a
    /// reviewer's name once per finding.
    func reviewComments(repositoryPath: String, number: Int) async throws -> [ReviewComment] {
        let result = try await gh(
            ["pr", "view", String(number), "--json", "reviews,comments"],
            in: repositoryPath,
        )
        var rows = [FeedbackEntry]()
        let feedback = try? JSONDecoder().decode(Feedback.self, from: Data(result.standardOutput.utf8))
        if let feedback {
            rows += (feedback.reviews ?? [])
                .map { FeedbackEntry(author: $0.author?.login, body: $0.body, kind: $0.state ?? "") }
            rows += (feedback.comments ?? [])
                .map { FeedbackEntry(author: $0.author?.login, body: $0.body, kind: "") }
        }

        return rows.enumerated().compactMap { index, row in
            let body = row.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard body.isEmpty == false || (row.kind.isEmpty == false && row.kind != "COMMENTED") else {
                return nil
            }

            return ReviewComment(id: index, author: row.author ?? "unknown", body: body, kind: row.kind)
        }
    }

    /// A pull request's body and full feedback timeline, for the
    /// conversation view; throws like ``reviewComments`` does.
    func conversation(repositoryPath: String, number: Int) async throws -> (body: String, events: [ReviewComment]) {
        let body = try await pullRequestDetail(repositoryPath: repositoryPath, number: number).body
        return try await (body, reviewComments(repositoryPath: repositoryPath, number: number))
    }

    // MARK: Internal

    /// The prompt for working on an issue.
    static func issuePrompt(number: Int, title: String, body: String, context: String) -> String {
        prompt(
            heading: "Work on issue #\(number): \(title)",
            body: body,
            context: context,
            closing: "Commit your work. Do not push.",
        )
    }

    /// The prompt for working on a pull request already checked out.
    static func pullRequestPrompt(number: Int, title: String, body: String, context: String) -> String {
        prompt(
            heading: "Continue pull request #\(number): \(title)",
            body: body,
            context: context,
            closing: "The branch is checked out here. Commit your work. Do not push.",
        )
    }
}

// MARK: - Private

private extension GitHubClient {
    struct TitledBody: Decodable {
        let title: String
        let body: String?
        let headRefName: String?
    }

    struct IssueRow: Decodable {
        let number: Int
        let title: String
    }

    struct Feedback: Decodable {
        // Either list is absent when the pull request has none.
        // swiftlint:disable discouraged_optional_collection
        let reviews: [FeedbackRow]?
        let comments: [FeedbackRow]?
        // swiftlint:enable discouraged_optional_collection
    }

    struct FeedbackRow: Decodable {
        let author: Author?
        let body: String?
        let state: String?
    }

    /// One collected feedback row before filtering, whichever source
    /// it came from.
    struct FeedbackEntry {
        let author: String?
        let body: String?
        let kind: String
    }

    struct Author: Decodable {
        let login: String?
    }

    static func prompt(heading: String, body: String, context: String, closing: String) -> String {
        var parts = [heading]
        if body.isEmpty == false {
            parts.append(body)
        }
        if context.isEmpty == false {
            parts.append("Additional context from the user:\n" + context)
        }
        parts.append(closing)
        return parts.joined(separator: "\n\n")
    }
}
