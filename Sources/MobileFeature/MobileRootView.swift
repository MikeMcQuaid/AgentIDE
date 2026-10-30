#if os(iOS)
    import SanductorDomain
    import SanductorInterface
    import SanductorRemote
    import SwiftUI

    /// The iPhone's repository navigation and selected agent terminal.
    public struct MobileRootView: View {
        // MARK: Lifecycle

        public init(model: MobileModel) {
            self.model = model
        }

        // MARK: Public

        public var body: some View {
            NavigationStack {
                content
                    .navigationTitle("Sanductor")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
                    .navigationDestination(item: $model.selection) { session in
                        MobileTerminalScreen(model: model, session: session)
                    }
                    .sheet(isPresented: $showsSettings) { MobileSettings(model: model) }
                    .sheet(item: $newRepository) { repository in
                        MobileNewSession(model: model, repository: repository.name)
                    }
                    .alert(
                        "Trust this Mac?",
                        isPresented: hostTrustPresented,
                        presenting: model.pendingHostKey,
                    ) { hostKey in
                        Button("Cancel", role: .cancel) {
                            model.deactivate()
                            model.error = "The host key has not been trusted."
                        }
                        Button("Trust") { model.trustHost(hostKey) }
                    } message: { key in
                        Text("Verify this fingerprint on your Mac:\n" + SSHCredentials.fingerprint(key))
                    }
            }
            .interfaceFont(.body)
            .onAppear {
                if model.configuration.isValid == false {
                    showsSettings = true
                }
            }
        }

        // MARK: Private

        private static let titleSpacing: CGFloat = 6

        @Bindable private var model: MobileModel
        @State private var showsSettings = false
        @State private var newRepository: Repository?

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Self.titleSpacing) {
                    MobileAppIcon()
                    Text("Sanductor").interfaceFont(.headline, weight: .semibold)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            ToolbarItem(placement: .topBarLeading) {
                if model.isConnected || model.isConnecting {
                    Button("Disconnect", systemImage: "network.slash") { model.disconnect() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                        .help("Disconnect")
                        .disabled(model.isCreating)
                } else {
                    connectButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if model.isConnected {
                    NewSessionMenu(repositories: model.repositories.map { name in
                        Repository(
                            name: name,
                            path: name,
                            fullName: model.sidebar.first { $0.name == name && $0.owner != nil }?.fullName,
                        )
                    }) { newRepository = $0 }
                }
            }
        }

        private var hostTrustPresented: Binding<Bool> {
            Binding(
                get: { model.pendingHostKey != nil },
                set: { presented in
                    if presented == false {
                        model.pendingHostKey = nil
                    }
                },
            )
        }

        private var connectButton: some View {
            Button("Connect", systemImage: "network") {
                if model.configuration.isValid {
                    model.reconnect()
                } else {
                    showsSettings = true
                }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(model.isDisconnected ? Color.blue : .primary)
            .help("Connect")
        }

        @ViewBuilder private var content: some View {
            if model.configuration.isValid == false {
                ContentUnavailableView(
                    "Connect to your Mac",
                    systemImage: "network",
                    description: Text("Open Settings to add your SSH connection."),
                )
            } else if model.isConnected == false {
                if let error = model.error {
                    VStack {
                        ContentUnavailableView(
                            "Could not connect", systemImage: "wifi.exclamationmark", description: Text(error),
                        )
                        Button("Reconnect") { model.reconnect() }.buttonStyle(.glassProminent)
                    }
                } else if model.isDisconnected {
                    ContentUnavailableView {
                        Text("Disconnected")
                    } description: {
                        Text("Your agents are still running on your Mac.")
                        Text("Choose \(Image(systemName: "network")) Connect to return.")
                            .accessibilityLabel("Choose Connect to return.")
                    }
                } else {
                    LaunchProgressView("Connecting", progress: model.progress)
                }
            } else {
                MobileSidebar(model: model, newRepository: $newRepository)
            }
        }
    }

    private struct MobileTerminalScreen: View {
        // MARK: Internal

        let model: MobileModel
        let session: MobileSession

        var body: some View {
            ZStack {
                if model.isConnected, handedOff == false {
                    terminal
                }
                if handedOff {
                    VStack {
                        Text("This terminal is controlled on your Mac.")
                        Button("Take control") { handedOff = false; ready = false; model.reconnect() }
                            .buttonStyle(.glassProminent)
                    }
                    .padding()
                    .background(.regularMaterial)
                } else if let error = model.error, model.isConnected == false {
                    VStack {
                        Text(error)
                        Button("Reconnect") { model.reconnect() }.buttonStyle(.glassProminent)
                    }
                    .padding()
                    .background(.regularMaterial)
                } else if ready == false || model.isConnected == false {
                    LaunchProgressView(
                        "Opening agent",
                        waitingOn: model.isConnected ? "the terminal's first frame" : "the SSH connection",
                    )
                    .background(.background)
                }
            }
            .navigationTitle(model.sessions.first { $0.id == session.id }?.branch ?? session.branch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Terminal appearance", systemImage: "circle.lefthalf.filled") { dark.toggle() }
            }
            .onChange(of: model.connectionGeneration) { _, _ in ready = false }
        }

        // MARK: Private

        @AppStorage("phoneTerminalDark")
        private var dark = false
        @State private var ready = false
        @State private var handedOff = false

        private var terminal: some View {
            MobileTerminal(
                model: model,
                session: session,
                onReady: { ready = true },
                onHandoff: { handedOff = true },
                dark: dark,
            )
            .id(model.connectionGeneration)
            .allowsHitTesting(ready && handedOff == false)
        }
    }
#endif
