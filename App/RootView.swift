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

    /// Internal so the extension file's toggle button can drive it.
    @AppStorage("showsUtilityPane")
    var showsUtilityPane = true

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
            FlavourIcon.apply()
            finderFocusRequest = 0
            runningShells = Set(runningShellPaths.split(separator: "\n").map(String.init))
            rememberedTabs = Self.decodeTabs(worktreeTabs)
            await dependencies.dashboard.poll()
        }
        // Sleep sometimes kills the sandbox tmux server; sessions
        // running at sleep that are gone at wake resume themselves,
        // while surviving or deliberately closed ones are left alone.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            sessionsBeforeSleep = runningWorktreePaths
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            let snapshot = sessionsBeforeSleep
            sessionsBeforeSleep = []
            Task { await resumeKilled(sleepSnapshot: snapshot) }
        }
        // Idle sleep is blocked while any agent or shell runs, since
        // the machine sleeping mid-response cuts them off.
        .onChange(of: hasLiveWork, initial: true) {
            sleepInhibitor.update(hasLiveWork: hasLiveWork)
        }
        // Reopening the app resumes the restored worktree's most
        // recent conversation: the default workflow is picking up
        // where the last session left off. Only the launch's
        // restored selection qualifies, never later clicks.
        .onChange(of: dependencies.dashboard.selection?.id) {
            guard hasAutoResumed == false, let item = dependencies.dashboard.selection else {
                return
            }

            hasAutoResumed = true
            let stored = UserDefaults.standard.string(forKey: "selectedWorktreePath")
            guard item.worktree.path == stored, item.session == nil,
                  dependencies.service.wasIntentionallyClosed(worktreePath: item.worktree.path) == false,
                  item.pastSessions.isEmpty == false
                  || dependencies.service.hasRecordedSession(worktreePath: item.worktree.path)
            else {
                return
            }

            // The pane fills with progress before the resume starts,
            // so the conversation list never flashes first.
            isAutoResuming = true
            Task {
                await resumeLatest(in: item)
                isAutoResuming = false
            }
        }
    }

    // MARK: Private

    /// Slim enough for icon-and-truncated-text rows while staying
    /// wider than the traffic lights band.
    private static let sidebarRange = 150.0 ... 440.0
    private static let utilityRange = 340.0 ... 1_200.0
    private static let primaryMinimum: CGFloat = 420
    private static let stripSpacing: CGFloat = 4

    /// The utility header row's height: the tab capsules plus the
    /// row's padding. The floating toggle centres in the same height
    /// so hiding the pane never moves it.
    private static let toggleRowHeight: CGFloat = 30

    /// The selected conversation's worktree on the repository page,
    /// nil when none exists; the review surfaces follow it. Internal
    /// so the extension file's tabs can read it.
    @State private var conversationWorktreePath: String?

    /// Whether the launch's one automatic resume has run, so later
    /// selection changes never launch anything by themselves.
    @State private var hasAutoResumed = false

    /// Fills the primary pane with progress while the launch resume
    /// runs, instead of flashing the conversation list first.
    @State private var isAutoResuming = false

    /// The worktrees with running sessions when the machine slept,
    /// so wake can resume exactly the ones sleep killed.
    @State private var sessionsBeforeSleep: Set<String> = []

    /// Blocks idle sleep while agents or shells run, since sleeping
    /// mid-response cuts agents off.
    @State private var sleepInhibitor: SleepInhibitor = .init()

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

    /// Pane widths, persisted so the layout restores on relaunch;
    /// the dividers write them directly.
    @AppStorage("sidebarWidth")
    private var sidebarWidth = 300.0
    @AppStorage("utilityPaneWidth")
    private var utilityPaneWidth = 480.0

    /// Whether anything is running that idle sleep would interrupt.
    private var hasLiveWork: Bool {
        runningShells.isEmpty == false || runningWorktreePaths.isEmpty == false
    }

    @ViewBuilder private var detail: some View {
        if dependencies.dashboard.showsNewSession {
            // The middle pane, never a sheet.
            NewSessionPane(model: dependencies.dashboard)
        } else if dependencies.dashboard.showsRepositoryFinder {
            RepositoryFinderPane(model: dependencies.dashboard)
        } else if let item = dependencies.dashboard.selection {
            split(for: item)
        } else {
            ContentUnavailableView(
                "No worktree selected",
                systemImage: "rectangle.stack",
                description: Text("Pick a worktree on the left or create a session."),
            )
        }
    }

    private func split(for item: WorktreeItem) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                sessionStrip(for: item)
                primary(for: item)
            }
            // With the utility pane hidden its toggle overlays the
            // session strip's empty right end, in exactly the spot
            // the pane header shows it, so it never moves on toggle.
            .overlay(alignment: .topTrailing) {
                if showsUtilityPane == false {
                    utilityToggleButton
                        .frame(height: Self.toggleRowHeight)
                        .padding(.trailing, Self.stripSpacing)
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
            // A stale conversation focus must not survive switching
            // to another sidebar item.
            conversationWorktreePath = nil
            utilityTabIndex = rememberedTabs[item.worktree.path] ?? utilityTabIndex
        }
        .onChange(of: utilityTabIndex) {
            rememberedTabs[item.worktree.path] = utilityTabIndex
            worktreeTabs = rememberedTabs
                .map { $0.key + "\t" + String($0.value) }
                .sorted()
                .joined(separator: "\n")
        }
    }

    /// One conversations UI everywhere: a live session shows its
    /// terminal; anything else shows the conversation list, scoped
    /// to the worktree or covering the whole repository on its page;
    /// a worktree with nothing to list offers the new session form.
    @ViewBuilder
    private func primary(for item: WorktreeItem) -> some View {
        if isAutoResuming, item.session == nil {
            ProgressView("Resuming conversation…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let session = item.session {
            agentTerminal(for: session)
                .id(session.name)
                // Dropped files stage into the shared workspace (the
                // sandbox cannot read host paths) and their staged
                // paths type into the agent.
                .dropDestination(for: URL.self) { urls, _ in
                    dropFiles(urls, into: session.name)
                }
        } else if item.worktree.path == item.worktree.repositoryPath {
            RepositorySessionsView(
                repository: repository(of: item),
                service: dependencies.service,
                onNewSession: { newSession(for: item) },
                // The review surfaces follow the selected
                // conversation's worktree, so clicking around the
                // repository page retargets Review and PRs.
                onWorktreeFocus: { conversationWorktreePath = $0 },
                onResumed: { await dependencies.dashboard.refresh() },
            )
        } else if item.pastSessions.isEmpty == false {
            RepositorySessionsView(
                repository: repository(of: item),
                service: dependencies.service,
                worktreePath: item.worktree.path,
                onNewSession: { newSession(for: item) },
                onResumed: { await sessionStarted() },
            )
        } else {
            CreateSessionPane(
                worktree: item.worktree,
                model: dependencies.dashboard,
                canResume: dependencies.service.hasRecordedSession(worktreePath: item.worktree.path),
                onResume: { await resumeLatest(in: item) },
                onStarted: { await sessionStarted() },
            )
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
                switchedUtility(for: item, conversationPath: conversationWorktreePath)
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
            shellTerminal(for: item.worktree) {
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
}
