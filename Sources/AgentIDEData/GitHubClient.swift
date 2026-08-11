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

    /// Which pull requests a listing covers.
    public enum ListScope: Hashable, Sendable {
        /// Open and closed pull requests from one branch.
        case branch(String)
        /// Open pull requests the authenticated user created.
        case mine
        /// Every open pull request.
        case open
    }

    /// The repository's pull requests for a scope, with dashboard
    /// state.
    public func pullRequests(
        repositoryPath: String,
        scope: ListScope = .open,
    ) async throws -> [PullRequestSummary] {
        let result = try await gh(Self.listArguments(scope: scope), in: repositoryPath)
        return Self.summaries(fromJSON: result.standardOutput)
    }

    /// The authenticated user's login followed by their
    /// organisations, for the repository finder's owner step.
    public func organisations(directory: String) async throws -> [String] {
        let user = try await gh(["api", "user", "--jq", ".login"], in: directory)
        let organisations = try await gh(
            ["api", "user/orgs?per_page=100", "--paginate", "--jq", ".[].login"],
            in: directory,
        )
        let login = user.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([login] + organisations.standardOutput.split(separator: "\n").map(String.init))
            .filter { $0.isEmpty == false }
    }

    /// Every repository under one owner, as `owner/name`, most
    /// recently pushed first.
    public func repositories(owner: String, directory: String) async throws -> [String] {
        let result = try await gh(
            ["repo", "list", owner, "--limit", "1000", "--json", "nameWithOwner", "--jq", ".[].nameWithOwner"],
            in: directory,
        )
        return result.standardOutput.split(separator: "\n").map(String.init)
    }

    /// Clones a repository into a directory, named after the
    /// repository, using the host's credentials.
    public func clone(fullName: String, into directory: String) async throws {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        try await gh(["repo", "clone", fullName, name], in: directory)
    }

    /// Opens a pull request from the worktree's branch. With a
    /// repository pull request template the body comes from it
    /// (which `--fill` would ignore) and the title from `title`;
    /// without one `--fill` takes both from the commits.
    public func createPullRequest(worktreePath: String, title: String) async throws -> String {
        var arguments = ["pr", "create"]
        if let template = Self.pullRequestTemplate(in: worktreePath), title.isEmpty == false {
            arguments += ["--title", title, "--body-file", template]
        } else {
            arguments += ["--fill"]
        }
        return try await gh(arguments, in: worktreePath)
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
        // `--comments` omits inline file comments, where review bots
        // leave their findings, so they join separately.
        let inline = await inlineComments(repositoryPath: repositoryPath, number: number)
            .compactMap { row -> String? in
                let body = row.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard body.isEmpty == false else {
                    return nil
                }

                return (row.author ?? "unknown") + ": " + body
            }
            .joined(separator: "\n\n")
        let checks = try? await gh(
            ["pr", "checks", String(number)],
            in: repositoryPath,
            allowFailure: true,
        )
        return [
            view?.standardOutput,
            inline.isEmpty ? nil : "Inline review comments:\n\n" + inline,
            checks?.standardOutput,
        ]
        .compactMap(\.self)
        .joined(separator: "\n\n")
    }

    // MARK: Internal

    /// The `gh pr list` invocation for a scope; separated for tests.
    /// The default `gh pr list` limit of 30 hid pull requests on
    /// busy repositories, so worktree branches failed to match.
    static let listLimit = 200

    /// The repository's pull request template file, nil without one.
    static func pullRequestTemplate(in worktreePath: String) -> String? {
        [
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/pull_request_template.md",
            "PULL_REQUEST_TEMPLATE.md",
            "docs/PULL_REQUEST_TEMPLATE.md",
        ]
        .map { worktreePath + "/" + $0 }
        .first { FileManager.default.fileExists(atPath: $0) }
    }

    static func listArguments(scope: ListScope) -> [String] {
        let fields = "number,title,url,headRefName,baseRefName,state,mergeable,reviewDecision,"
            + "statusCheckRollup,isDraft,autoMergeRequest,headRefOid"
        var arguments = ["pr", "list", "--json", fields, "--limit", String(Self.listLimit)]
        switch scope {
        case let .branch(branch):
            arguments += ["--head", branch, "--state", "all"]

        case .mine:
            arguments += ["--author", "@me"]

        case .open:
            break
        }
        return arguments
    }

    /// Parses `gh pr list` JSON into summaries; separated for tests.
    static func summaries(fromJSON json: String) -> [PullRequestSummary] {
        guard let data = json.data(using: .utf8) else {
            return []
        }

        let rows = (try? JSONDecoder().decode([PullRequestRow].self, from: data)) ?? []
        return rows.map { row in
            let rollup = row.statusCheckRollup ?? []
            return PullRequestSummary(
                number: row.number,
                title: row.title,
                url: row.url,
                headBranch: row.headRefName,
                mergeable: row.mergeable ?? "",
                reviewDecision: row.reviewDecision ?? "",
                checks: Self.aggregateChecks(rollup),
                failingCheckLinks: rollup
                    .filter { ($0.conclusion ?? $0.state ?? "").uppercased() == "FAILURE" }
                    .compactMap(\.detailsUrl), // swiftformat:disable:this acronyms
                baseBranch: row.baseRefName ?? "",
                state: row.state ?? "OPEN",
                isDraft: row.isDraft ?? false,
                hasAutomerge: row.autoMergeRequest != nil,
                headOID: row.headRefOid ?? "",
            )
        }
    }

    @discardableResult
    func gh(
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

    // MARK: Private

    /// Present when automerge is enabled; the contents are unused.
    private struct AutoMergeRow: Decodable {
        // Presence is the signal.
    }

    private struct PullRequestRow: Decodable {
        let number: Int
        let title: String
        let url: String
        let headRefName: String
        let baseRefName: String?
        let state: String?
        let mergeable: String?
        let reviewDecision: String?
        // Optional because older gh versions omit the field.
        // swiftlint:disable:next discouraged_optional_boolean
        let isDraft: Bool?
        let autoMergeRequest: AutoMergeRow?
        let headRefOid: String?
        // Absent from the JSON when a pull request has no checks.
        // swiftlint:disable:next discouraged_optional_collection
        let statusCheckRollup: [CheckRow]?
    }

    private struct CheckRow: Decodable {
        let state: String?
        let conclusion: String?
        // The property must match gh's JSON key exactly.
        // swiftformat:disable:next acronyms
        let detailsUrl: String?
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
}
