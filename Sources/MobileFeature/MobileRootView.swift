#if os(iOS)
    import AgentIDEDomain
    import AgentIDEInterface
    import AgentIDERemote
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
                    .navigationTitle("AgentIDE")
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
        private static let rowSpacing: CGFloat = 3
        private static let rowInset: CGFloat = 8
        private static let agentIconSize: CGFloat = 14
        private static let minimumTouchSize: CGFloat = 44
        private static let avatarCornerRadius: CGFloat = 4

        @ScaledMetric(relativeTo: .headline)
        private var avatarSize = 20.0

        @Bindable private var model: MobileModel
        @State private var showsSettings = false
        @State private var newRepository: Repository?

        private var nameStyle: NameStyle = .init()

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Self.titleSpacing) {
                    MobileAppIcon()
                    Text("AgentIDE").interfaceFont(.headline, weight: .semibold)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                repositoryList
            }
        }

        private var repositoryList: some View {
            List {
                if model.repositories.isEmpty {
                    ContentUnavailableView(
                        "No repositories",
                        systemImage: "folder",
                        description: Text("Add a repository on your Mac first."),
                    )
                }
                ForEach(
                    MobileSession.sortedRepositories(
                        model.repositories, sessions: model.sessions, sidebar: model.sidebar,
                    ),
                    id: \.self,
                ) { repository in
                    let sessions = MobileSession.sortedSessions(
                        model.sessions.filter { $0.repository == SessionName.slug(repository) },
                        worktrees: model.sidebar.first { $0.name == repository }?.worktrees ?? [],
                    )
                    newSessionButton(repository, count: Set(sessions.map { $0.directory ?? $0.name }).count)
                    ForEach(sessions) { session in
                        sessionButton(session)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Self.rowSpacing,
                    leading: Self.rowInset,
                    bottom: Self.rowSpacing,
                    trailing: Self.rowInset,
                ))
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { await model.refresh() }
        }

        private func sessionButton(_ session: MobileSession) -> some View {
            Button { model.selection = session } label: {
                HStack(alignment: .top, spacing: Self.titleSpacing) {
                    SessionStatusIcon(status: .running, activity: session.activity)
                        .interfaceFont(.callout)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.branch).font(nameStyle.font).lineLimit(1)
                        HStack(spacing: Self.titleSpacing) {
                            if let agent = session.agent {
                                AgentIcon(agent, size: Self.agentIconSize)
                            } else {
                                Image(systemName: "terminal").accessibilityLabel("Shell")
                            }
                            if let status = session.gitStatus {
                                Text(status.summary).help(GitWorktreeStatus.countsHelp)
                            }
                        }
                        .interfaceFont(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Self.rowInset)
        }

        private func newSessionButton(_ repository: String, count: Int = 0) -> some View {
            Button {
                newRepository = Repository(name: repository, path: repository)
            } label: {
                HStack(spacing: Self.titleSpacing) {
                    OwnerAvatar(owner: model.sidebar.first { $0.name == repository }?.owner, size: avatarSize)
                        .clipShape(RoundedRectangle(cornerRadius: Self.avatarCornerRadius))
                    Text(repository)
                        .interfaceFont(.headline, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if count > 0 {
                        Text("(" + String(count) + ")")
                            .interfaceFont(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(count) + " worktrees with sessions")
                    }
                    Image(systemName: "plus")
                        .interfaceFont(.body, weight: .semibold)
                        .foregroundStyle(.primary)
                        .frame(minWidth: Self.minimumTouchSize, minHeight: Self.minimumTouchSize)
                        .glassEffect(.regular.interactive(), in: Circle())
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Self.minimumTouchSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .accessibilityLabel("New session in " + repository)
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
