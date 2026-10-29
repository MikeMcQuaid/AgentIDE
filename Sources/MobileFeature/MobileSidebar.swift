#if os(iOS)
    import AgentIDEDomain
    import AgentIDEInterface
    import SwiftUI

    struct MobileSidebar: View {
        // MARK: Lifecycle

        init(model: MobileModel, newRepository: Binding<Repository?>) {
            self.model = model
            _newRepository = newRepository
        }

        // MARK: Internal

        var body: some View {
            List {
                if model.repositories.isEmpty {
                    ContentUnavailableView(
                        "No repositories",
                        systemImage: "folder",
                        description: Text("Add a repository on your Mac first."),
                    )
                }
                groupedRows
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Self.rowSpacing,
                        leading: Self.rowInset,
                        bottom: Self.rowSpacing,
                        trailing: Self.rowInset,
                    ))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    SidebarModePicker(mode: $mode)
                    if mode == .repository {
                        RepositorySortPicker(sort: $repositorySort).padding(.trailing, Self.rowInset)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { await model.refresh() }
            .sheet(item: $pendingBlock) { target in
                WorkBlockEditor(
                    target: target,
                    block: pendingExistingBlock,
                    targets: model.sidebarTargets,
                    loadSources: { await model.sidebarRequest(.sources(repositoryPath: $0)) },
                    save: { await model.editBlock($0, replacing: $1) },
                    dismiss: { pendingBlock = nil },
                )
            }
            .task(id: mode == .status && model.isConnected) {
                guard mode == .status, model.isConnected else {
                    return
                }

                while Task.isCancelled == false {
                    _ = await model.sidebarRequest(.refreshStatus)
                    try? await Task.sleep(for: .seconds(RefreshCadence.sidebarStatusSeconds))
                }
            }
        }

        // MARK: Private

        private static let blockLines = 2
        private static let titleSpacing: CGFloat = 6
        private static let rowSpacing: CGFloat = 3
        private static let rowInset: CGFloat = 8
        private static let agentIconSize: CGFloat = 14
        private static let minimumTouchSize: CGFloat = 44
        private static let avatarCornerRadius: CGFloat = 4

        @AppStorage("sidebarMode")
        private var mode: SidebarMode = .repository
        @AppStorage("sidebarRepositorySort")
        private var repositorySort: RepositorySort = .activity
        @ScaledMetric(relativeTo: .headline)
        private var avatarSize = 20.0
        @State private var pendingExistingBlock: WorkBlock?
        @State private var pendingBlock: SidebarTarget?
        @Binding private var newRepository: Repository?

        private let model: MobileModel
        private var nameStyle: NameStyle = .init()

        @ViewBuilder private var groupedRows: some View {
            if mode == .status {
                ForEach(model.statusGroups, id: \.status) { group in
                    SidebarStatusGroup(status: group.status, count: group.sessions.count) {
                        ForEach(group.sessions) { session in sessionButton(session) }
                    }
                }
            } else {
                ForEach(
                    model.repositoryNames(sortedBy: repositorySort),
                    id: \.self,
                ) { repository in
                    let sessions = MobileSession.sortedSessions(
                        model.sessions.filter { $0.repository == SessionName.slug(repository) },
                        worktrees: model.sidebar.first { $0.name == repository }?.worktrees ?? [],
                    )
                    if sessions.isEmpty == false {
                        newSessionButton(repository, count: Set(sessions.map { $0.directory ?? $0.name }).count)
                        ForEach(sessions) { session in
                            sessionButton(session)
                        }
                    }
                }
            }
        }

        private func newSessionButton(_ repository: String, count: Int) -> some View {
            Button {
                newRepository = Repository(name: repository, path: repository)
            } label: {
                HStack(spacing: Self.titleSpacing) {
                    OwnerAvatar(owner: model.sidebar.first { $0.name == repository }?.owner, size: avatarSize)
                        .clipShape(RoundedRectangle(cornerRadius: Self.avatarCornerRadius))
                    Text(model.sidebar.first { $0.name == repository }?.fullName ?? repository)
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

        private func sessionButton(_ session: MobileSession) -> some View {
            Button { model.selection = session } label: {
                HStack(alignment: .top, spacing: Self.titleSpacing) {
                    if model.sidebarEntry(for: session)?.block != nil {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Blocked")
                    } else {
                        SessionStatusIcon(status: .running, activity: session.activity)
                            .interfaceFont(.callout)
                    }
                    sessionLabel(session)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Self.rowInset)
            .contextMenu {
                if let entry = model.sidebarEntry(for: session) {
                    Button(entry.block == nil ? "Block…" : "Edit block…") {
                        pendingExistingBlock = entry.block
                        pendingBlock = entry.target
                    }
                }
            }
        }

        private func sessionLabel(_ session: MobileSession) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.branch).font(nameStyle.font).lineLimit(1)
                HStack(spacing: Self.titleSpacing) {
                    if mode == .status {
                        let name = model.sidebarEntry(for: session)?.target.repository ?? session.repository
                        let repository = model.sidebar.first { $0.name == name }
                        OwnerAvatar(owner: repository?.owner, size: Self.agentIconSize)
                        Text(name)
                            .lineLimit(1)
                            .accessibilityLabel(repository?.fullName ?? name)
                    }
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
                if let block = model.sidebarEntry(for: session)?.block {
                    Text("Blocked: " + block.dependency.label)
                        .lineLimit(Self.blockLines)
                        .interfaceFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
#endif
