import AgentIDEDomain
import Foundation

// MARK: - AgentLaunchOptions

/// The user's model and effort picks; nil keeps the agent's default.
public struct AgentLaunchOptions: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates options.
    public init(model: String? = nil, effort: String? = nil) {
        self.model = model
        self.effort = effort
    }

    // MARK: Public

    /// The model name, nil for the agent's default.
    public let model: String?

    /// The reasoning effort, nil for the agent's default.
    public let effort: String?
}

// MARK: - WorktreeSlot

/// A prepared place to launch an agent: repository, branch and path.
struct WorktreeSlot {
    let repository: Repository
    let branch: String
    let path: String
}

// MARK: - Prompt sources and search

public extension SessionService {
    /// Starts an agent in an existing worktree and pastes the prompt,
    /// used by one-click remediation and the per-worktree create pane.
    func launchAgent(
        in worktree: Worktree,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        let sessionName = SessionName.make(repository: worktree.repositoryName, branch: worktree.branch, agent: agent)
        try? await tmux.killSession(name: sessionName)
        let slot = WorktreeSlot(
            repository: Repository(name: worktree.repositoryName, path: worktree.repositoryPath),
            branch: worktree.branch,
            path: worktree.path,
        )
        return try await start(prompt: prompt, agent: agent, options: options, slot: slot)
    }

    /// The models and efforts an agent's pickers offer when discovery
    /// has not (yet) answered.
    func launchChoices(for agent: AgentKind) -> (models: [String], efforts: [String]) {
        let runner = runner(for: agent)
        return (runner.models, runner.efforts)
    }

    // nil means "keep the fallback list", which callers treat
    // differently from an empty answer.
    // swiftlint:disable discouraged_optional_collection

    /// Asks the agent's CLI for its current models; nil when the
    /// command fails or yields nothing. The CLI runs inside the
    /// sandbox, where sessions run it anyway; running it as the host
    /// user made macOS prompt for broad disk access.
    func discoverModels(for agent: AgentKind) async -> [String]? {
        // swiftlint:enable discouraged_optional_collection
        let runner = runner(for: agent)
        let argv = launcher.command(
            payload: runner.modelListingCommand.joined(separator: " ") + " </dev/null",
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-model-listing",
        )
        let result = try? await processes.run(argv, workingDirectory: nil, environment: [:])
        guard let result, result.succeeded else {
            return nil
        }

        let models = runner.parseModelList(result.standardOutput)
        return models.isEmpty ? nil : models
    }

    /// Creates a session whose prompt is a GitHub issue plus the
    /// user's additional context.
    func createSession(
        fromIssue number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        let issue = try await github.issue(repositoryPath: repository.path, number: number)
        let prompt = GitHubClient.issuePrompt(
            number: number,
            title: issue.title,
            body: issue.body,
            context: context,
        )
        let branch = await availableBranch(repository: repository, prompt: "issue-\(number)-" + issue.title)
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let slot = WorktreeSlot(repository: repository, branch: branch, path: worktreePath)
        return try await start(prompt: prompt, agent: agent, options: options, slot: slot)
    }

    /// Creates a session on a pull request's own branch: the worktree
    /// is checked out with `gh pr checkout`, so pushes and pulls
    /// track the pull request directly.
    func createSession(
        fromPullRequest number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        let detail = try await github.pullRequestDetail(repositoryPath: repository.path, number: number)
        let prompt = GitHubClient.pullRequestPrompt(
            number: number,
            title: detail.title,
            body: detail.body,
            context: context,
        )
        let worktreePath = try await createDetachedWorktreePath(repository: repository, name: "pr-\(number)")
        try await github.checkoutPullRequest(worktreePath: worktreePath, number: number)
        let branch = detail.headBranch.isEmpty ? "pr-\(number)" : detail.headBranch
        let slot = WorktreeSlot(repository: repository, branch: branch, path: worktreePath)
        return try await start(prompt: prompt, agent: agent, options: options, slot: slot)
    }

    /// Fetches and prunes the repository's remotes.
    func fetch(repository: Repository) async throws {
        try await git.fetch(repositoryPath: repository.path)
    }

    /// Fetches origin and hard-resets the main checkout to its
    /// default branch.
    func fetchAndReset(repository: Repository) async throws {
        try await git.fetchAndReset(repositoryPath: repository.path)
    }

    /// Fetches, then rebases the worktree onto the signed-rebase
    /// target with every replayed commit re-signed, aborting cleanly
    /// on conflict. This is how unsigned agent commits become
    /// pushable: the sandbox cannot sign and a hook blocks unsigned
    /// pushes, so signing always happens here on the host.
    func rebaseSigned(worktree: Worktree) async throws {
        try await git.fetch(repositoryPath: worktree.path)
        let branch = await git.currentBranch(worktreePath: worktree.path) ?? worktree.branch
        let target = await signedRebaseTarget(worktreePath: worktree.path, branch: branch)
        try await git.rebaseSigned(worktreePath: worktree.path, onto: target)
    }

    /// The ref a signed rebase lands on. The branch's own origin ref
    /// wins when it exists, every commit unique to it verifies and
    /// local commits sit on top needing signatures: rebasing there
    /// signs only the new commits, so pushed history keeps its
    /// hashes. Anything else falls back to origin/HEAD, re-signing
    /// the whole branch.
    func signedRebaseTarget(worktreePath: String, branch: String) async -> String {
        let remote = "origin/" + branch
        guard await git.remoteBranchExists(worktreePath: worktreePath, branch: branch),
              await git.allCommitsSigned(worktreePath: worktreePath, range: "origin/HEAD.." + remote),
              await (git.commitCount(worktreePath: worktreePath, range: remote + "..HEAD") ?? 0) > 0
        else {
            return "origin/HEAD"
        }

        return remote
    }

    /// A repository's recency for sidebar ordering: its worktrees
    /// always count, the main checkout only while a session runs in
    /// it, so resuming on the repository page bumps the repository
    /// without its everyday churn reordering anything. Here rather
    /// than the main file for length; internal, unlike the extension.
    internal static func repositoryActivity(of group: RepositoryGroup) -> Int {
        let worktrees = group.items.dropFirst().map(\.lastActivityAt).max() ?? 0
        guard let main = group.items.first, main.session != nil else {
            return worktrees
        }

        return max(worktrees, main.lastActivityAt)
    }

    /// The repository's open issues, for the issue source picker.
    func openIssues(repository: Repository) async -> [IssueSummary] {
        await github.openIssues(repositoryPath: repository.path)
    }

    /// The repository's open pull requests, for the PR source picker.
    func openPullRequests(repository: Repository) async throws -> [PullRequestSummary] {
        try await github.pullRequests(repositoryPath: repository.path, scope: .open)
    }

    /// The user's login and organisations, for the repository
    /// finder's owner step. Empty when GitHub is unreachable.
    func organisations() async -> [String] {
        await (try? github.organisations(directory: paths.repositoriesDirectory)) ?? []
    }

    /// Every repository under one owner on GitHub. Empty when GitHub
    /// is unreachable.
    func repositories(owner: String) async -> [String] {
        await (try? github.repositories(owner: owner, directory: paths.repositoriesDirectory)) ?? []
    }

    /// Clones a repository into the shared workspace when it is not
    /// already there, returning it either way.
    func cloneRepository(fullName: String) async throws -> Repository {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        let path = paths.repositoriesDirectory + "/" + name
        if FileManager.default.fileExists(atPath: path) == false {
            try await github.clone(fullName: fullName, into: paths.repositoriesDirectory)
        }
        return Repository(name: name, path: path, fullName: fullName)
    }

    /// The file's uncommitted line numbers, for the editor's gutter.
    func changedLineNumbers(worktreePath: String, file: String) async -> Set<Int> {
        await git.changedLineNumbers(worktreePath: worktreePath, file: file)
    }

    /// The worktree's current HEAD commit, for cache freshness.
    func headCommit(worktreePath: String) async -> String? {
        await git.headCommit(worktreePath: worktreePath)
    }

    /// Starts an agent on an issue in an existing worktree: the issue
    /// becomes the prompt, plus the user's context.
    func launchAgent(
        fromIssue number: Int,
        in worktree: Worktree,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        let issue = try await github.issue(repositoryPath: worktree.repositoryPath, number: number)
        let prompt = GitHubClient.issuePrompt(
            number: number,
            title: issue.title,
            body: issue.body,
            context: context,
        )
        return try await launchAgent(in: worktree, prompt: prompt, agent: agent, options: options)
    }

    /// The base ref whole-branch reviews diff against: the branch's
    /// open pull request base when one exists, otherwise the
    /// repository's default branch.
    func reviewBase(for worktree: Worktree) async -> String? {
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let summaries = try? await github.pullRequests(
            repositoryPath: worktree.repositoryPath,
            scope: .branch(worktree.branch),
        )
        if let base = summaries?.first(where: { $0.state == "OPEN" })?.baseBranch, base.isEmpty == false {
            return "origin/" + base
        }
        return await git.defaultBaseRef(of: repository)
    }

    /// The worktree's tracked and untracked files, gitignore aware,
    /// for the fuzzy finder.
    func listFiles(worktreePath: String) async -> [String] {
        let result = try? await processes.run(
            ["rg", "--files", "--sort", "path"],
            workingDirectory: worktreePath,
            environment: [:],
        )
        return (result?.standardOutput ?? "")
            .split(separator: "\n")
            .prefix(Self.fileListLimit)
            .map { String($0.trimmingPrefix("./")) }
    }

    /// Searches a worktree with ripgrep; empty on no matches.
    func search(worktreePath: String, query: String) async -> [SearchHit] {
        guard query.isEmpty == false else {
            return []
        }

        let arguments = [
            "rg", "--no-heading", "--line-number", "--color", "never",
            "--smart-case", "--max-count", "5", "--max-columns", "300", query, ".",
        ]
        let result = try? await processes.run(
            arguments,
            workingDirectory: worktreePath,
            environment: [:],
        )
        let lines = (result?.standardOutput ?? "").split(separator: "\n").prefix(Self.searchHitLimit)
        return lines.compactMap { line in
            // path:line:text, with any further colons kept in the text.
            var fields = line
                .split(separator: ":", maxSplits: Self.searchFieldSplits, omittingEmptySubsequences: false)
                .makeIterator()
            guard let fileField = fields.next(),
                  let lineField = fields.next(),
                  let textField = fields.next(),
                  let lineNumber = Int(lineField)
            else {
                return nil
            }

            let file = String(fileField.trimmingPrefix("./"))
            return SearchHit(file: file, line: lineNumber, text: String(textField))
        }
    }

    // MARK: Internal

    /// Adds a detached worktree, letting `gh pr checkout` create the
    /// branch afterwards.
    func createDetachedWorktreePath(repository: Repository, name: String) async throws -> String {
        let path = try await worktreeContainer(repository: repository) + "/" + name
        try await git.addDetachedWorktree(repository: repository, at: path)
        return path
    }
}
