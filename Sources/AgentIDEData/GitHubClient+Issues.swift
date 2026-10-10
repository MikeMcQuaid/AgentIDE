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
    /// The repository's open issues, newest first. The limit is
    /// named: `gh` defaults to thirty, which quietly cut the picker
    /// short on any repository with a real backlog.
    func openIssues(repositoryPath: String, limit: Int = GitHubClient.pickerLimit) async -> [IssueSummary] {
        let result = try? await gh(
            ["issue", "list", "--state", "open", "--json", "number,title", "--limit", String(limit)],
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
            // The reference belongs in the commit, not only the pull
            // request: a commit that closes an issue says so wherever
            // it is read, and the pull request inherits it anyway.
            closing: "Commit your work, with \"Fixes #\(number)\" in the commit message."
                + " Do not push.",
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

    /// The prompt every GitHub source composes: what to work on, its
    /// body, the user's context and how to finish.
    internal static func prompt(heading: String, body: String, context: String, closing: String) -> String {
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
}
