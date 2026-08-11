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
        // Plain panes with our own dividers: the navigation split
        // view's floating toggle covered nearby controls and split
        // views neither persisted divider positions nor honoured
        // ideal widths on this OS. The sidebar never hides; it
        // resizes down to a slim strip instead.
        HStack(spacing: 0) {
            DashboardView(model: dependencies.dashboard)
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarMaterial())
                .ignoresSafeArea(.container, edges: .top)
            PaneDivider(width: $sidebarWidth, range: Self.sidebarRange, controlsLeadingPane: true)
                .ignoresSafeArea(.container, edges: .top)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .sheet(isPresented: sessionManagerBinding) {
            SessionManagerSheet(service: dependencies.service) {
                dependencies.dashboard.showsSessionManager = false
            }
        }
        .task {
            finderFocusRequest = 0
            runningShells = Set(runningShellPaths.split(separator: "\n").map(String.init))
            rememberedTabs = Self.decodeTabs(worktreeTabs)
            await dependencies.dashboard.poll()
        }
    }

    // MARK: Private

    /// Slim enough for icon-and-truncated-text rows while staying
    /// wider than the traffic lights band.
    private static let sidebarRange = 150.0 ... 440.0
    private static let utilityRange = 340.0 ... 1_200.0
    private static let primaryMinimum: CGFloat = 420
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
    @AppStorage("showsUtilityPane")
    private var showsUtilityPane = true

    /// Pane widths, persisted so the layout restores on relaunch;
    /// the dividers write them directly.
    @AppStorage("sidebarWidth")
    private var sidebarWidth = 300.0
    @AppStorage("utilityPaneWidth")
    private var utilityPaneWidth = 480.0

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

    /// The tab bubbles and the pane toggle.
    private var utilityHeader: some View {
        HStack(spacing: Self.stripSpacing) {
            // The tabs scroll when the pane narrows, so the toggle
            // beside them can never be squeezed out.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.stripSpacing) {
                    UtilityTabStrip()
                }
            }
            Spacer(minLength: 0)
            utilityToggleButton
                .fixedSize()
        }
        .padding(Self.stripSpacing)
    }

    private func split(for item: WorktreeItem) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                sessionStrip(for: item, selection: $sessionTab)
                primary(for: item)
            }
            // With the utility pane hidden its toggle overlays the
            // session strip's empty right end, so the pane can always
            // come back by mouse without pushing the pane down.
            .overlay(alignment: .topTrailing) {
                if showsUtilityPane == false {
                    utilityToggleButton.padding(Self.stripSpacing)
                }
            }
            .frame(
                minWidth: Self.primaryMinimum,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top,
            )
            .ignoresSafeArea(.container, edges: .top)
            if showsUtilityPane {
                PaneDivider(width: $utilityPaneWidth, range: Self.utilityRange, controlsLeadingPane: false)
                    .ignoresSafeArea(.container, edges: .top)
                utilityPane(for: item)
                    .frame(width: utilityPaneWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The utility pane: the shared tab header over the content, so
    /// the current tab is always visible whichever tab shows.
    /// Restores the worktree's remembered tab whenever the selection
    /// changes, so each worktree keeps its own pane.
    private func utilityPane(for item: WorktreeItem) -> some View {
        VStack(spacing: 0) {
            utilityHeader
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
            shellLayer(for: item)
                .opacity(showsShell ? 1 : 0)
                .allowsHitTesting(showsShell)
            if showsShell == false, showsBrowser == false {
                // Identity keyed by worktree, so switching in the
                // sidebar always rebuilds the pane's state. The
                // backgrounds must not expand into the ignored
                // titlebar safe area, where they would paint over
                // the tab header above.
                switchedUtility(for: item)
                    .id("utility-" + path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.background, ignoresSafeAreaEdges: [])
            }
            // Like the shell, a visited browser stays mounted so its
            // page survives tab switches without reloading.
            if visitedBrowsers.contains(path) {
                BrowserView()
                    .id("browser-" + path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, ignoresSafeAreaEdges: [])
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

    /// The shell tab's layer, always mounted while its shell runs so
    /// the terminal survives tab switches at a constant size.
    @ViewBuilder
    private func shellLayer(for item: WorktreeItem) -> some View {
        let path = item.worktree.path
        if runningShells.contains(path) {
            TerminalPaneView(
                command: dependencies.service.hostShellCommand(worktree: item.worktree),
            ) {
                runningShells.remove(path)
                runningShellPaths = runningShells.sorted().joined(separator: "\n")
            }
            .id("shell-" + path)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            startShellButton(for: path)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
