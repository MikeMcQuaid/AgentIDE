import AgentIDEData
import AgentIDEDomain
import TerminalUI

/// Session creation: every entry point funnels through one runner
/// that closes the form, refreshes and selects the new worktree.
public extension DashboardModel {
    /// Creates a session from a typed prompt.
    func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run {
            try await service.createSession(
                repository: repository,
                prompt: prompt,
                agent: agent,
                options: options,
            )
        }
    }

    /// Creates a session working on a GitHub issue.
    func createSession(
        fromIssue number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run {
            try await service.createSession(
                fromIssue: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Creates a session on a pull request's own branch.
    func createSession(
        fromPullRequest number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run {
            try await service.createSession(
                fromPullRequest: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Starts an agent in an existing worktree.
    func launchAgent(
        in worktree: Worktree,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run {
            try await service.launchAgent(in: worktree, prompt: prompt, agent: agent, options: options)
        }
    }

    /// Starts an agent on an open issue in an existing worktree.
    func launchAgent(
        fromIssue number: Int,
        in worktree: Worktree,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run {
            try await service.launchAgent(
                fromIssue: number,
                in: worktree,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Runs a session-creation action, closing the page, refreshing
    /// and selecting the new session's worktree so the agent is on
    /// screen immediately.
    private func run(_ work: () async throws -> String) async {
        do {
            screenError = nil
            let sessionName = try await work()
            showsNewSession = false
            await refresh()
            if let created = groups.flatMap(\.items).first(where: { $0.session?.name == sessionName }) {
                selection = created
            }
        } catch {
            // The new-session page is still on screen and cannot
            // show the Errors tab, so the failure shows inline too.
            screenError = error.localizedDescription
            ErrorLog.shared.report(error.localizedDescription)
        }
    }
}
