import AgentIDEDomain
import Foundation

extension DashboardModel {
    /// Hands the window's own choices to the shared workspace, where
    /// `agentide new` reads them: a session started from a phone
    /// then offers exactly what the New Session form offers, already
    /// set to what it was last set to.
    func publishSessionDefaults() {
        let defaults = UserDefaults.standard
        // The form keeps one model and effort, for the agent it is
        // set to, so they are published under that agent's name:
        // Codex's model offered for a Claude session would be a
        // model Claude has never heard of.
        let chosen = defaults.string(forKey: "agentKind") ?? AgentKind.claudeCode.rawValue
        var values: [(key: String, value: String)] = [
            ("repository", selection?.worktree.repositoryName ?? repositories.first?.name ?? ""),
            ("agent", chosen),
            ("repositories", repositories.map(\.name).joined(separator: " ")),
        ]
        for agent in AgentKind.allCases {
            let choices = launchChoices(for: agent)
            let isChosen = agent.rawValue == chosen
            values.append((agent.rawValue + "-models", choices.models.joined(separator: " ")))
            values.append((agent.rawValue + "-efforts", choices.efforts.joined(separator: " ")))
            values.append((
                agent.rawValue + "-model",
                isChosen ? defaults.string(forKey: "agentModel") ?? "" : "",
            ))
            values.append((
                agent.rawValue + "-effort",
                isChosen ? defaults.string(forKey: "agentEffort") ?? "" : "",
            ))
        }
        service.publishSessionDefaults(values)
    }
}
