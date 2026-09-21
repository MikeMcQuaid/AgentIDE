import AgentIDEData
import AgentIDEDomain
import DashboardFeature
import SwiftUI
import TerminalUI

// MARK: - ReviewSettingsPane

/// Review preferences independent of the main agent's session defaults.
struct ReviewSettingsPane: View {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some View {
        Form {
            Section("Reviewer") {
                Picker("Default reviewer", selection: $reviewAgent) {
                    Text("Other agent").tag("")
                    ForEach(AgentKind.allCases, id: \.self) { agent in
                        Text(agent.displayName).tag(agent.rawValue)
                    }
                }
                Text("Review panes start with this agent; you can choose another before reviewing.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(AgentKind.allCases, id: \.self) { agent in
                ReviewAgentSettings(agent: agent, choices: dashboard.launchChoices)
            }
            Text("Model and effort changes apply to the next review. New-session defaults stay separate.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage(AppSettings.reviewAgentKey)
    private var reviewAgent = ""
}

// MARK: - ReviewAgentSettings

private struct ReviewAgentSettings: View {
    // MARK: Lifecycle

    init(agent: AgentKind, choices: @escaping (AgentKind) -> AgentChoices) {
        self.agent = agent
        self.choices = choices
        _model = AppStorage(wrappedValue: "", AppSettings.reviewModelKey(for: agent))
        _effort = AppStorage(wrappedValue: "", AppSettings.reviewEffortKey(for: agent))
    }

    // MARK: Internal

    let agent: AgentKind
    let choices: (AgentKind) -> AgentChoices

    var body: some View {
        Section(agent.displayName) {
            AgentOptionPickers(
                agent: .constant(agent),
                model: $model,
                effort: $effort,
                choices: choices,
                showsAgent: false,
            )
        }
    }

    // MARK: Private

    @AppStorage private var model: String
    @AppStorage private var effort: String
}
