#if os(iOS)
    import AgentIDEInterface
    import AgentIDERemote
    import SwiftUI

    struct MobileSettings: View {
        // MARK: Lifecycle

        init(model: MobileModel) {
            self.model = model
            _configuration = State(initialValue: model.configuration)
        }

        // MARK: Internal

        var body: some View {
            NavigationStack {
                form
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            BusyButton(
                                "Connect",
                                busy: "Connecting",
                                prominent: true,
                                disabled: configuration.isValid == false,
                            ) {
                                model.configuration = configuration
                                model.selection = nil
                                model.reconnect()
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                    }
                    .onAppear { focus = true }
            }
        }

        // MARK: Private

        private static let terminalSizeRange = 8.0 ... 30.0

        @Environment(\.dismiss)
        private var dismiss
        @State private var configuration: SSHConfiguration
        @FocusState private var focus: Bool
        @AppStorage(CodeStyle.fontSizeKey)
        private var terminalSize: Double = CodeStyle.defaultPointSize

        private let model: MobileModel
        private var nameStyle: NameStyle = .init()

        private var form: some View {
            Form {
                connection
                Section("Terminal") {
                    Stepper("Font size: " + String(Int(terminalSize)), value: $terminalSize, in: Self.terminalSizeRange)
                }
                Section {
                    Picker("Herdr session", selection: $configuration.session) {
                        Text("agentide").tag("agentide")
                        Text("agentide-dev").tag("agentide-dev")
                    }
                    .pickerStyle(.menu)
                } footer: { Text("Use agentide for the installed Mac app, or agentide-dev for a development build.") }
                Section {
                    Text(model.publicKey).font(nameStyle.font).textSelection(.enabled)
                    ShareLink("Share public key", item: model.publicKey)
                } header: { Text("Phone's SSH key") } footer: {
                    Text("Add this public key to the sandbox user's authorised keys on your Mac. "
                        + "The private key stays in this phone's Keychain.")
                }
                Section {
                    Button("Forget saved host key", role: .destructive) { model.forgetHost() }
                } footer: { Text("Use this only after verifying that your Mac's SSH host key has changed.") }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        private var connection: some View {
            Section {
                TextField("IP address or hostname", text: $configuration.host)
                    .keyboardType(.URL)
                    .focused($focus)
                LabeledContent("SSH port") {
                    TextField("22", value: $configuration.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }
                LabeledContent("Sandbox username") {
                    HStack(spacing: 0) {
                        Text(SSHConfiguration.usernamePrefix).foregroundStyle(.secondary)
                        TextField("Mac username", text: Binding(
                            get: { String(configuration.username.dropFirst(SSHConfiguration.usernamePrefix.count)) },
                            set: { configuration.username = SSHConfiguration.usernamePrefix + $0 },
                        ))
                    }
                }
            } header: { Text("SSH connection") } footer: {
                Text("Use your Mac's IP address or hostname. Enter your Mac username after the fixed sandbox prefix.")
            }
        }
    }
#endif
