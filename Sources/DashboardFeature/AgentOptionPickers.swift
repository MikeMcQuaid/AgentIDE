import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The agent, model and effort dropdowns shared by every session
/// creation surface. Each opens on something: the last pick where it
/// still exists, and what the agent itself would run otherwise, so
/// changing agent leaves a model and an effort chosen rather than two
/// empty pickers and a form that will not start.
public struct AgentOptionPickers: View {
    // MARK: Lifecycle

    /// Creates the pickers; public so the Settings window can offer
    /// the same controls the session forms use.
    public init(
        agent: Binding<AgentKind>,
        model: Binding<String>,
        effort: Binding<String>,
        choices: @escaping (AgentKind) -> AgentChoices,
    ) {
        _agent = agent
        _model = model
        _effort = effort
        self.choices = choices
    }

    // MARK: Public

    public var body: some View {
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
                ForEach(choices(agent).models, id: \.self) { name in
                    Text(AgentOptionName.display(name, named: choices(agent).names)).tag(name)
                }
            }
            .hoverHelp("The model the agent uses")
            Picker("Effort", selection: $effort) {
                ForEach(choices(agent).efforts, id: \.self) { name in
                    Text(AgentOptionName.display(name, named: choices(agent).names)).tag(name)
                }
            }
            .hoverHelp("How much reasoning the agent spends")
        }
        .labelsHidden()
        // On appearance as well as on change: the agent, model and
        // effort all persist across launches now, but discovery can
        // change what a CLI offers between runs, and a persisted pair
        // must never combine a model one agent knows with another.
        .onAppear { resetUnavailableChoices() }
        .onChange(of: agent) { resetUnavailableChoices() }
    }

    // MARK: Internal

    @Binding var agent: AgentKind
    @Binding var model: String
    @Binding var effort: String

    let choices: (AgentKind) -> AgentChoices

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let agentIconSize: CGFloat = 8

    /// A model or effort picked for one agent may not exist on
    /// another, and neither does the empty string a form opens on the
    /// first time: either way the picker falls back to what this
    /// agent itself would run, so there is always something chosen to
    /// start with.
    private func resetUnavailableChoices() {
        let available = choices(agent)
        if available.models.contains(model) == false {
            model = available.defaultModel
        }
        if available.efforts.contains(effort) == false {
            effort = available.defaultEffort
        }
    }
}
