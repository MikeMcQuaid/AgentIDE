import AgentIDEDomain
import Foundation

/// Talks to GitHub through the host user's authenticated `gh` CLI;
/// the sandbox never sees these credentials.
public struct GitHubClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client.
    public init(runner: any ProcessRunner) {
        self.runner = runner
    }

    // MARK: Public

    /// The repository's open pull requests with dashboard state.
    public func pullRequests(repositoryPath: String) async throws -> [PullRequestSummary] {
        let fields = "number,title,url,headRefName,mergeable,reviewDecision,statusCheckRollup"
        let result = try await gh(["pr", "list", "--json", fields], in: repositoryPath)
        guard let data = result.standardOutput.data(using: .utf8) else {
            return []
        }

        let rows = (try? JSONDecoder().decode([PullRequestRow].self, from: data)) ?? []
        return rows.map { row in
            PullRequestSummary(
                number: row.number,
                title: row.title,
                url: row.url,
                headBranch: row.headRefName,
                mergeable: row.mergeable ?? "",
                reviewDecision: row.reviewDecision ?? "",
                checks: Self.aggregateChecks(row.statusCheckRollup ?? []),
            )
        }
    }

    /// Opens a pull request from the worktree's branch, filling the
    /// title and body from its commits.
    public func createPullRequest(worktreePath: String) async throws -> String {
        try await gh(["pr", "create", "--fill"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enables automerge for a pull request.
    public func enableAutomerge(repositoryPath: String, number: Int) async throws {
        try await gh(["pr", "merge", String(number), "--auto", "--squash"], in: repositoryPath)
    }

    /// Merges a pull request immediately.
    public func merge(repositoryPath: String, number: Int) async throws {
        try await gh(["pr", "merge", String(number), "--squash"], in: repositoryPath)
    }

    /// The review comments and check results of a pull request, as
    /// text an agent can act on.
    public func remediationContext(repositoryPath: String, number: Int) async -> String {
        let view = try? await gh(["pr", "view", String(number), "--comments"], in: repositoryPath)
        let checks = try? await gh(
            ["pr", "checks", String(number)],
            in: repositoryPath,
            allowFailure: true,
        )
        return [view?.standardOutput, checks?.standardOutput]
            .compactMap(\.self)
            .joined(separator: "\n\n")
    }

    // MARK: Private

    private struct PullRequestRow: Decodable {
        let number: Int
        let title: String
        let url: String
        let headRefName: String
        let mergeable: String?
        let reviewDecision: String?
        // Absent from the JSON when a pull request has no checks.
        // swiftlint:disable:next discouraged_optional_collection
        let statusCheckRollup: [CheckRow]?
    }

    private struct CheckRow: Decodable {
        let state: String?
        let conclusion: String?
    }

    private let runner: any ProcessRunner

    private static func aggregateChecks(_ rows: [CheckRow]) -> String {
        let states = rows.map { ($0.conclusion ?? $0.state ?? "").uppercased() }
        guard states.isEmpty == false else {
            return ""
        }

        if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) {
            return "FAILURE"
        }
        if states.allSatisfy({ $0 == "SUCCESS" || $0 == "NEUTRAL" || $0 == "SKIPPED" }) {
            return "SUCCESS"
        }
        return "PENDING"
    }

    @discardableResult
    private func gh(
        _ arguments: [String],
        in directory: String?,
        allowFailure: Bool = false,
    ) async throws -> ProcessResult {
        let result = try await runner.run(["gh"] + arguments, workingDirectory: directory, environment: [:])
        guard result.succeeded || allowFailure else {
            throw CommandError(command: "gh " + arguments.joined(separator: " "), result: result)
        }

        return result
    }
}
