import AgentIDEDomain
import Foundation

public extension SessionService {
    /// A background launch shares the normal sandbox funnel without
    /// writing into a foreground launch's progress. Retries reuse its worktree.
    func launchScheduledPrompt(_ prompt: ScheduledPrompt, due: Date) async throws -> String {
        var service = self
        service.progress = silentLaunchReporter
        service.herdr.progress = silentLaunchReporter
        let repository = Repository(
            name: URL(filePath: prompt.repositoryPath).lastPathComponent,
            path: prompt.repositoryPath,
        )
        try requireSandboxWorkspace(repository.path)
        let branch = prompt.branch(for: due)
        let worktrees = try await git.worktrees(of: repository)
        let existing = worktrees.first { $0.branch == branch }
        let path: String
        if let existing {
            path = existing.path
            if await hasLiveSession(worktreePath: path) {
                return SessionName.make(repository: repository.name, branch: branch, agent: prompt.agent)
            }
        } else {
            path = try await service.createWorktreePath(repository: repository, branch: branch)
        }
        return try await service.start(
            prompt: prompt.prompt,
            agent: prompt.agent,
            options: AgentLaunchOptions(
                model: prompt.model.isEmpty ? nil : prompt.model,
                effort: prompt.effort.isEmpty ? nil : prompt.effort,
            ),
            slot: WorktreeSlot(repository: repository, branch: branch, path: path),
        )
    }
}
