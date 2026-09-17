import AgentIDEDomain

/// Sessions started from a repository security advisory, whose
/// branch, commits and pull request must say nothing about it.
public extension SessionService {
    /// The branch every advisory session works on, numbered on
    /// collision: a name summarising the prompt would have said what
    /// the fix was for before the advisory was published.
    static let advisoryBranch = "improvements"

    /// Creates a session whose prompt is a security advisory plus the
    /// user's additional context, on a branch that names nothing.
    func createSession(
        fromAdvisory ghsaID: String,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        await clearQuarantine(for: agent)
        async let probed = probeVersion(of: agent)
        let advisory = try await github.securityAdvisory(repositoryPath: repository.path, ghsaID: ghsaID)
        let branch = await availableBranch(repository: repository, base: Self.advisoryBranch)
        let worktreePath = try await createWorktreePath(repository: repository, branch: branch)
        let slot = WorktreeSlot(repository: repository, branch: branch, path: worktreePath)
        return try await start(
            prompt: GitHubClient.advisoryPrompt(advisory, context: context),
            agent: agent,
            options: options,
            slot: slot,
            probed: probed,
        )
    }

    /// Starts an agent on a security advisory in an existing
    /// worktree: the advisory becomes the prompt, plus the user's
    /// context.
    func launchAgent(
        fromAdvisory ghsaID: String,
        in worktree: Worktree,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async throws -> String {
        let advisory = try await github.securityAdvisory(repositoryPath: worktree.repositoryPath, ghsaID: ghsaID)
        return try await launchAgent(
            in: worktree,
            prompt: GitHubClient.advisoryPrompt(advisory, context: context),
            agent: agent,
            options: options,
        )
    }

    /// The repository's advisories in triage or draft, for the
    /// advisory source picker.
    func securityAdvisories(repository: Repository) async -> [SecurityAdvisorySummary] {
        await github.securityAdvisories(repositoryPath: repository.path)
    }

    /// The base itself when no branch holds it, otherwise the first
    /// numbered variant none does.
    internal func availableBranch(repository: Repository, base: String) async -> String {
        guard await git.branchExists(repository: repository, branch: base) else {
            return base
        }

        var attempt = 2
        while await git.branchExists(repository: repository, branch: "\(base)-\(attempt)") {
            attempt += 1
        }
        return "\(base)-\(attempt)"
    }
}
