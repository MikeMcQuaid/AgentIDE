import AgentIDEDomain
import Foundation

extension DashboardModel {
    /// Hands `agentide new` what only the app can know: which
    /// repositories exist and what each agent offers. What was last
    /// chosen is not published here, since the command chooses too
    /// and its choice must survive the next poll.
    func publishSessionChoices() {
        var values: [(key: String, value: String)] = [
            ("repositories", repositories.map(\.name).joined(separator: " ")),
        ]
        for agent in AgentKind.allCases {
            let choices = launchChoices(for: agent)
            values.append((agent.rawValue + "-models", choices.models.joined(separator: " ")))
            values.append((agent.rawValue + "-efforts", choices.efforts.joined(separator: " ")))
        }
        service.publishSessionChoices(values)
        // Paths, one per line, since a path can hold anything a
        // `key=value` line cannot.
        service.publishHostDirectories(
            groups.flatMap(\.items).filter(\.worktree.isHostDirectory).map(\.worktree.path),
        )
    }

    /// Remembers what a session was just started with, so the next
    /// one, here or from a phone, comes back to it. The model and
    /// effort are kept under their agent's name: the form keeps one
    /// pair, and Codex's model means nothing to Claude.
    func rememberLaunch(sessionName: String) {
        let defaults = UserDefaults.standard
        guard let agent = AgentKind.allCases.first(where: { sessionName.hasSuffix("--" + $0.rawValue) }) else {
            return
        }

        service.publishSessionChoices([
            ("repository", SessionName.repositorySlug(of: sessionName) ?? ""),
            ("agent", agent.rawValue),
            (agent.rawValue + "-model", defaults.string(forKey: "agentModel") ?? ""),
            (agent.rawValue + "-effort", defaults.string(forKey: "agentEffort") ?? ""),
        ])
    }
}
