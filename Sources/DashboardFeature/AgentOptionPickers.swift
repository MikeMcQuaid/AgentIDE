import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The agent, model and effort dropdowns shared by every session
/// creation surface. Neither model nor effort has a default: until
/// one has been picked the picker stands empty and the form refuses
/// to start, and afterwards the last pick is what comes back.
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
                    Label {
                        Text(kind.displayName)
                    } icon: {
                        Image(kind.iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                    }
                    .tag(kind)
                }
            }
            .hoverHelp("The agent CLI to run")
            Picker("Model", selection: $model) {
                // The unpicked state is a row of its own: a
                // selection matching no row leaves the picker blank,
                // which reads as a bug rather than as a choice
                // waiting to be made.
                Text("Choose…").tag("")
                ForEach(choices(agent).models, id: \.self) { name in
                    Text(Self.display(name)).tag(name)
                }
            }
            .hoverHelp("The model the agent uses; pick one to start")
            Picker("Effort", selection: $effort) {
                Text("Choose…").tag("")
                ForEach(choices(agent).efforts, id: \.self) { name in
                    Text(Self.display(name)).tag(name)
                }
            }
            .hoverHelp("How much reasoning the agent spends; pick one to start")
        }
        .labelsHidden()
        // On appearance as well as on change: the agent, model and
        // effort all persist across launches now, but discovery can
        // change what a CLI offers between runs, and a persisted pair
        // must never combine a model one agent knows with another.
        .onAppear { resetUnavailableChoices() }
        .onChange(of: agent) { resetUnavailableChoices() }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let agentIconSize: CGFloat = 8

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
    /// another; it is unpicked rather than sent, so the agent that
    /// is chosen now gets a choice of its own.
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
