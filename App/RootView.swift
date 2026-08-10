import AgentIDEDomain
import DashboardFeature
import PRFeature
import ReviewFeature
import SessionFeature
import SwiftUI
import TerminalUI

/// The main window: the dashboard sidebar on the left; on the right,
/// segmented controls selecting the worktree's sessions over a split
/// of the sandboxed agent and a collapsible utility pane.
struct RootView: View {
    // MARK: Internal

    let dependencies: AppDependencies

    /// Persisted as an index so the menu commands can drive it too;
    /// internal so the extension file can read it.
    @AppStorage("utilityTabIndex")
    var utilityTabIndex = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DashboardView(model: dependencies.dashboard)
                .navigationSplitViewColumnWidth(min: Self.sidebarMinimum, ideal: Self.sidebarIdeal)
        } detail: {
            detail
        }
        .sheet(isPresented: newSessionBinding) {
            NewSessionSheet(model: dependencies.dashboard)
        }
        // The repository sidebar's visibility round-trips through
        // storage so the View menu can drive and describe it.
        .onChange(of: showsRepositorySidebar) {
            columnVisibility = showsRepositorySidebar ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) {
            showsRepositorySidebar = columnVisibility != .detailOnly
        }
        .task {
            finderFocusRequest = 0
            columnVisibility = showsRepositorySidebar ? .all : .detailOnly
            await dependencies.dashboard.poll()
        }
    }

    // MARK: Private

    private static let sidebarMinimum: CGFloat = 240
    private static let sidebarIdeal: CGFloat = 300
    private static let primaryMinimum: CGFloat = 420
    private static let utilityMinimum: CGFloat = 340
    private static let stripSpacing: CGFloat = 4
    private static let tabHorizontalPadding: CGFloat = 8
    private static let tabVerticalPadding: CGFloat = 3
    private static let tabSelectedOpacity = 0.25

    /// Internal so the session tabs extension file can drive it.
    @State private var sessionTab: String = Self.activeTabID

    /// Focus requests from the finder menu items, cleared at launch
    /// so a request from the previous run cannot fire.
    @AppStorage("finderFocusRequest")
    private var finderFocusRequest = 0

    /// Worktrees whose shell is running; started explicitly, removed
    /// when the shell process exits, so a quit shell shows its start
    /// button again.
    @State private var runningShells: Set<String> = []

    /// Worktrees whose browser has been opened; it stays mounted so
    /// its page survives tab switches.
    @State private var visitedBrowsers: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("showsUtilityPane")
    private var showsUtilityPane = true
    @AppStorage("showsRepositorySidebar")
    private var showsRepositorySidebar = true

    @ViewBuilder private var detail: some View {
        if let item = dependencies.dashboard.selection {
            split(for: item)
                .onChange(of: item.id) { sessionTab = initialTab(for: item) }
        } else {
            ContentUnavailableView(
                "No worktree selected",
                systemImage: "rectangle.stack",
                description: Text("Pick a worktree on the left or create a session."),
            )
        }
    }

    /// The worktree's sessions as capsule tabs at the top of the
    /// primary pane; hidden when there is nothing to pick between.
    /// In-pane rather than in the window toolbar, whose items
    /// reflowed across the split on this OS.
    @ViewBuilder
    private func sessionStrip(for item: WorktreeItem) -> some View {
        if item.session != nil || item.pastSessions.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.stripSpacing) {
                    if let session = item.session {
                        sessionTabButton(title: sessionTitle(for: session), id: Self.activeTabID)
                    }
                    ForEach(item.pastSessions) { past in
                        sessionTabButton(title: pastTitle(for: past), id: past.id)
                    }
                }
                .padding(Self.stripSpacing)
            }
            .hoverHelp("The worktree's sessions: the live one and past conversations")
            Divider()
        }
    }

    private func sessionTabButton(title: String, id: String) -> some View {
        Button {
            sessionTab = id
        } label: {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, Self.tabHorizontalPadding)
                .padding(.vertical, Self.tabVerticalPadding)
                .background(
                    Capsule().fill(sessionTab == id ? Color.accentColor.opacity(Self.tabSelectedOpacity) : .clear),
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func split(for item: WorktreeItem) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                sessionStrip(for: item)
                primary(for: item)
            }
            .frame(
                minWidth: Self.primaryMinimum,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top,
            )
            if showsUtilityPane {
                utilityPane(for: item)
                    .frame(minWidth: Self.utilityMinimum, maxHeight: .infinity)
            }
        }
    }

    /// The utility pane's own header: its tabs, a New Session button
    /// and the pane toggle. In-pane so the controls can never cross
    /// the split into the primary pane.
    private func utilityPane(for item: WorktreeItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.stripSpacing) {
                UtilityTabStrip()
                Spacer(minLength: 0)
                Button {
                    dependencies.dashboard.newSessionRepository = Repository(
                        name: item.worktree.repositoryName,
                        path: item.worktree.repositoryPath,
                    )
                    dependencies.dashboard.showsNewSession = true
                } label: {
                    Label("New session", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .hoverHelp("Start a new agent session, prefilled with this repository")
                Button {
                    showsUtilityPane.toggle()
                } label: {
                    Label("Toggle utility pane", systemImage: "sidebar.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .hoverHelp("Hide the utility pane; View or Cmd-Shift-U brings it back")
            }
            .padding(Self.stripSpacing)
            Divider()
            utilityContent(for: item)
        }
    }

    @ViewBuilder
    private func primary(for item: WorktreeItem) -> some View {
        if sessionTab == Self.activeTabID, let session = item.session {
            TerminalPaneView(command: dependencies.service.attachCommand(sessionName: session.name))
                .id(session.name)
        } else if let past = item.pastSessions.first(where: { $0.id == sessionTab }) {
            PastSessionPane(
                past: past,
                item: item,
                onResumedHere: { await sessionStarted() },
                dependencies: dependencies,
            )
        } else if item.worktree.path == item.worktree.repositoryPath {
            // The repository page: its whole conversation history.
            // It stays inside the top safe area: rising into the
            // toolbar row left the header covered by the tab strip.
            RepositorySessionsView(
                repository: Repository(
                    name: item.worktree.repositoryName,
                    path: item.worktree.repositoryPath,
                    fullName: nil,
                ),
                service: dependencies.service,
            ) { await dependencies.dashboard.refresh() }
        } else {
            CreateSessionPane(
                worktree: item.worktree,
                model: dependencies.dashboard,
            ) { await sessionStarted() }
        }
    }

    /// A running shell stays mounted whichever tab shows, so its
    /// terminal survives tab switches; host tmux additionally keeps
    /// the shell alive across app restarts. Both layers always fill
    /// the pane, so tab switches never resize the hidden terminal; a
    /// resize would make the shell reprint its prompt, which reads as
    /// stray newlines. Shells start only from their button, and a
    /// quit shell (Ctrl-D) returns to it.
    private func utilityContent(for item: WorktreeItem) -> some View {
        let showsShell = utilityTab == .shell
        let showsBrowser = utilityTab == .browser
        let path = item.worktree.path
        return ZStack {
            if runningShells.contains(path) {
                TerminalPaneView(
                    command: dependencies.service.hostShellCommand(worktree: item.worktree),
                ) {
                    runningShells.remove(path)
                }
                .id("shell-" + path)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsShell ? 1 : 0)
                .allowsHitTesting(showsShell)
            } else if showsShell {
                startShellButton(for: path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showsShell == false, showsBrowser == false {
                // Identity keyed by worktree, so switching in the
                // sidebar always rebuilds the pane's state.
                switchedUtility(for: item)
                    .id("utility-" + path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.background)
            }
            // Like the shell, a visited browser stays mounted so its
            // page survives tab switches without reloading.
            if visitedBrowsers.contains(path) {
                BrowserView()
                    .id("browser-" + path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                    .opacity(showsBrowser ? 1 : 0)
                    .allowsHitTesting(showsBrowser)
            }
        }
        .task(id: item.id + String(utilityTabIndex)) {
            if utilityTab == .browser {
                visitedBrowsers.insert(path)
            }
        }
    }

    private func startShellButton(for path: String) -> some View {
        Button {
            runningShells.insert(path)
        } label: {
            Label("Start shell", systemImage: "terminal")
        }
        .controlSize(.large)
        .hoverHelp("Open a host-user shell here; it runs in host tmux and survives app restarts")
    }

    @ViewBuilder
    private func switchedUtility(for item: WorktreeItem) -> some View {
        switch utilityTab {
        case .shell:
            EmptyView()

        case .review:
            ReviewView(worktree: item.worktree, git: dependencies.git, service: dependencies.service)

        case .editor:
            EditorPane(worktreePath: item.worktree.path, service: dependencies.service)

        case .pullRequests:
            PullRequestsView(
                repository: Repository(name: item.worktree.repositoryName, path: item.worktree.repositoryPath),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
                branch: item.worktree.branch,
            )

        case .browser:
            BrowserView()

        case .message:
            FinalMessageView(item: item, service: dependencies.service)
        }
    }

    private func sessionStarted() async {
        await dependencies.dashboard.refresh()
        sessionTab = Self.activeTabID
    }
}
