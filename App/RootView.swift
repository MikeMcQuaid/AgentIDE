import AgentIDEDomain
import DashboardFeature
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
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(min: Self.sidebarMinimum, ideal: Self.sidebarIdeal)
        } detail: {
            detail
                .ignoresSafeArea(.container, edges: .top)
        }
        // Hiding the whole window toolbar took the traffic lights
        // with it. Instead only the split view's automatic sidebar
        // toggle is removed, so no toolbar ever forms; the panes
        // ignore the remaining titlebar inset and the configurator
        // keeps the titlebar transparent with its buttons visible.
        .toolbar(removing: .sidebarToggle)
        .background(WindowConfigurator())
        .sheet(isPresented: sessionManagerBinding) {
            SessionManagerSheet(service: dependencies.service) {
                dependencies.dashboard.showsSessionManager = false
            }
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
            runningShells = Set(runningShellPaths.split(separator: "\n").map(String.init))
            rememberedTabs = Self.decodeTabs(worktreeTabs)
            await dependencies.dashboard.poll()
        }
    }

    // MARK: Private

    private static let sidebarMinimum: CGFloat = 240
    private static let sidebarIdeal: CGFloat = 300
    private static let primaryMinimum: CGFloat = 420
    private static let utilityMinimum: CGFloat = 340
    private static let stripSpacing: CGFloat = 4

    @State private var sessionTab: String = Self.activeTabID

    /// Focus requests from the finder menu items, cleared at launch
    /// so a request from the previous run cannot fire.
    @AppStorage("finderFocusRequest")
    private var finderFocusRequest = 0

    /// Worktrees whose shell is running; started explicitly, removed
    /// when the shell process exits, so a quit shell shows its start
    /// button again.
    @State private var runningShells: Set<String> = []

    /// The same set persisted, so shells running at quit reattach
    /// automatically on the next launch; host tmux kept them alive.
    @AppStorage("runningShellPaths")
    private var runningShellPaths = ""

    /// Each worktree's last utility tab, persisted as
    /// path-tab-index lines so panes stay per-worktree.
    @AppStorage("worktreeTabs")
    private var worktreeTabs = ""
    @State private var rememberedTabs: [String: Int] = [:]

    /// Worktrees whose browser has been opened; it stays mounted so
    /// its page survives tab switches.
    @State private var visitedBrowsers: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("showsUtilityPane")
    private var showsUtilityPane = true
    @AppStorage("showsRepositorySidebar")
    private var showsRepositorySidebar = true

    @ViewBuilder private var detail: some View {
        if dependencies.dashboard.showsNewSession {
            // The middle pane, never a sheet.
            NewSessionPane(model: dependencies.dashboard)
        } else if dependencies.dashboard.showsRepositoryFinder {
            RepositoryFinderPane(model: dependencies.dashboard)
        } else if let item = dependencies.dashboard.selection {
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

    private var utilityToggleButton: some View {
        Button {
            showsUtilityPane.toggle()
        } label: {
            Label("Toggle utility pane", systemImage: "sidebar.right")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .hoverHelp(
            showsUtilityPane
                ? "Hide the utility pane; View or Cmd-Shift-U brings it back"
                : "Show the utility pane",
        )
    }

    private func split(for item: WorktreeItem) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                // With the utility pane hidden its toggle moves here,
                // so the pane can always be brought back by mouse.
                if showsUtilityPane == false {
                    HStack(spacing: Self.stripSpacing) {
                        Spacer(minLength: 0)
                        utilityToggleButton
                    }
                    .padding(Self.stripSpacing)
                    Divider()
                }
                sessionStrip(for: item, selection: $sessionTab)
                primary(for: item)
            }
            .frame(
                minWidth: Self.primaryMinimum,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top,
            )
            .ignoresSafeArea(.container, edges: .top)
            if showsUtilityPane {
                utilityPane(for: item)
                    .frame(minWidth: Self.utilityMinimum, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The utility pane's own header: its tabs and the pane toggle.
    /// In-pane so the controls can never cross the split into the
    /// primary pane. Restores the worktree's remembered tab whenever
    /// the selection changes, so each worktree keeps its own pane.
    private func utilityPane(for item: WorktreeItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.stripSpacing) {
                UtilityTabStrip()
                Spacer(minLength: 0)
                utilityToggleButton
            }
            .padding(Self.stripSpacing)
            Divider()
            utilityContent(for: item)
        }
        .task(id: item.worktree.path) {
            if let remembered = rememberedTabs[item.worktree.path] {
                utilityTabIndex = remembered
            }
        }
        .onChange(of: utilityTabIndex) {
            rememberedTabs[item.worktree.path] = utilityTabIndex
            worktreeTabs = rememberedTabs
                .map { $0.key + "\t" + String($0.value) }
                .sorted()
                .joined(separator: "\n")
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
                    runningShellPaths = runningShells.sorted().joined(separator: "\n")
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
            runningShellPaths = runningShells.sorted().joined(separator: "\n")
        } label: {
            Label("Start shell", systemImage: "terminal")
        }
        .controlSize(.large)
        .hoverHelp("Open a host-user shell here; it runs in host tmux and survives app restarts")
    }

    private func sessionStarted() async {
        await dependencies.dashboard.refresh()
        sessionTab = Self.activeTabID
    }
}
