import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The agent, model and effort dropdowns shared by every session
/// creation surface. An empty model or effort keeps the agent's
/// default.
struct AgentOptionPickers: View {
    // MARK: Internal

    @Binding var agent: AgentKind
    @Binding var model: String
    @Binding var effort: String

    let choices: (AgentKind) -> (models: [String], efforts: [String])

    var body: some View {
        HStack(spacing: Self.spacing) {
            Picker("Agent", selection: $agent) {
                ForEach(AgentKind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.iconSystemName).tag(kind)
                }
            }
            .hoverHelp("The agent CLI to run")
            Picker("Model", selection: $model) {
                Text("Default").tag("")
                ForEach(choices(agent).models, id: \.self) { name in
                    Text(Self.display(name)).tag(name)
                }
            }
            .hoverHelp("The model the agent uses; Default leaves it to the agent")
            Picker("Effort", selection: $effort) {
                Text("Default").tag("")
                ForEach(choices(agent).efforts, id: \.self) { name in
                    Text(Self.display(name)).tag(name)
                }
            }
            .hoverHelp("How much reasoning the agent spends; Default leaves it to the agent")
        }
        .labelsHidden()
        .onChange(of: agent) { resetUnavailableChoices() }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6

    /// Human-readable picker names: xhigh reads Extra High, gpt ids
    /// read GPT n and simple names capitalise.
    private static func display(_ name: String) -> String {
        if name == "xhigh" {
            return "Extra High"
        }
        if name.hasPrefix("gpt-") {
            return "GPT " + name.dropFirst("gpt-".count)
        }
        return name.allSatisfy(\.isLowercase) ? name.capitalized : name
    }

    /// A model or effort picked for one agent may not exist on
    /// another; fall back to the default rather than sending it.
    private func resetUnavailableChoices() {
        let available = choices(agent)
        if available.models.contains(model) == false {
            model = ""
        }
        if available.efforts.contains(effort) == false {
            effort = ""
        }
    }
}
