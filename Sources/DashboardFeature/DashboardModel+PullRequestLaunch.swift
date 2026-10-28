import Foundation
import SanductorData
import SanductorDomain

/// Starting an agent from the Pull requests tab, which has no form of
/// its own; split from the sessions file for length.
public extension DashboardModel {
    /// Starts an agent on a listed pull request: at once with the last
    /// agent, model and effort, as Shortcuts do, never moving the
    /// selection the list belongs to, or through the new session form.
    func startAgent(onPullRequest number: Int, repository: Repository, immediately: Bool) async {
        let defaults = UserDefaults.standard
        let agent = defaults.string(forKey: "agentKind").flatMap(AgentKind.init(rawValue:)) ?? .claudeCode
        let options = AgentLaunchOptions(
            model: defaults.string(forKey: "agentModel").flatMap { $0.isEmpty ? nil : $0 },
            effort: defaults.string(forKey: "agentEffort").flatMap { $0.isEmpty ? nil : $0 },
        )
        guard immediately else {
            launchRetry = LaunchRetry(
                repositoryPath: repository.path,
                worktreePath: nil,
                draft: LaunchDraft(text: "", source: .pullRequest, agent: agent, options: options, number: number),
            )
            openNewSession(for: repository)
            return
        }

        await createSession(
            fromPullRequest: number,
            repository: repository,
            context: "",
            agent: agent,
            options: options,
            reveals: false,
        )
    }
}
