#if os(iOS)
    import AgentIDEDomain
    import AgentIDEInterface
    import SwiftUI

    struct MobileNewSession: View {
        // MARK: Lifecycle

        init(model: MobileModel, repository: String) {
            self.model = model
            self.repository = repository
            let initialAgent = AgentKind(rawValue: model.defaults["agent"] ?? "") ?? .claudeCode
            _agent = State(initialValue: initialAgent)
            _modelName = State(initialValue: model.defaults[initialAgent.rawValue + "-model"] ?? "")
            _effort = State(initialValue: model.defaults[initialAgent.rawValue + "-effort"] ?? "")
        }

        // MARK: Internal

        var body: some View {
            NavigationStack {
                Group {
                    if model.isCreating {
                        LaunchProgressView("Starting session", progress: model.progress)
                    } else {
                        form
                    }
                }
                .navigationTitle("New session")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isCreating)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        BusyButton("Start", busy: "Starting", prominent: true, disabled: cannotStart) {
                            if await model.create(
                                repository: repository, agent: agent, model: modelName, effort: effort, prompt: prompt,
                            ) {
                                dismiss()
                            }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .interactiveDismissDisabled(model.isCreating)
                .onAppear { model.error = nil; focused = true }
                .onChange(of: agent) { _, agent in
                    modelName = model.defaults[agent.rawValue + "-model"] ?? ""
                    effort = model.defaults[agent.rawValue + "-effort"] ?? ""
                }
            }
        }

        // MARK: Private

        private static let promptLines = 5 ... 15

        @Environment(\.dismiss)
        private var dismiss
        @State private var agent: AgentKind
        @State private var modelName: String
        @State private var effort: String
        @State private var prompt = ""
        @FocusState private var focused: Bool

        private let model: MobileModel
        private let repository: String
        private var nameStyle: NameStyle = .init()

        private var cannotStart: Bool {
            prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isConnected == false
        }

        private var form: some View {
            Form {
                Section {
                    Text(repository).font(nameStyle.font)
                    Picker("Agent", selection: $agent) {
                        ForEach(AgentKind.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    TextField("Model (default when empty)", text: $modelName)
                    TextField("Effort (default when empty)", text: $effort)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Section("Prompt") {
                    TextField("What should the agent do?", text: $prompt, axis: .vertical)
                        .lineLimit(Self.promptLines)
                        .focused($focused)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }
#endif
