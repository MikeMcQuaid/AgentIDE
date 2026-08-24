import AgentIDEDomain
import Foundation

extension DashboardModel {
    /// Hands the window's own choices to the shared workspace, where
    /// `agentide new` reads them: a session started from a phone
    /// then offers exactly what the New Session form offers, already
    /// set to what it was last set to.
    func publishSessionDefaults() {
        let defaults = UserDefaults.standard
        var values: [(key: String, value: String)] = [
            ("repository", selection?.worktree.repositoryName ?? repositories.first?.name ?? ""),
            ("agent", defaults.string(forKey: "agentKind") ?? AgentKind.claudeCode.rawValue),
            ("model", defaults.string(forKey: "agentModel") ?? ""),
            ("effort", defaults.string(forKey: "agentEffort") ?? ""),
            ("repositories", repositories.map(\.name).joined(separator: " ")),
        ]
        for agent in AgentKind.allCases {
            let choices = launchChoices(for: agent)
            values.append((agent.rawValue + "-models", choices.models.joined(separator: " ")))
            values.append((agent.rawValue + "-efforts", choices.efforts.joined(separator: " ")))
        }
        service.publishSessionDefaults(values)
    }
}
