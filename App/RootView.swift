import AgentIDEDomain
import DashboardFeature
import SessionFeature
import SwiftUI

// MARK: - RootView

/// The main window: the dashboard sidebar on the left; on the right,
/// segmented controls selecting the worktree's sessions over a split
/// of the sandboxed agent and a collapsible utility pane.
struct RootView: View {
    // MARK: Internal

    let dependencies: AppDependencies

    /// Persisted as the tab's name rather than an index, so
    /// reordering the tabs can never repoint a saved selection;
    /// internal so the extension file can read it.
    @AppStorage("utilityTab")
    var utilityTabName = UtilityTab.review.rawValue

    /// Internal so the extension file's toggle button can drive it.
    @AppStorage("showsUtilityPane")
    var showsUtilityPane = true

    /// Whether a middle page covers the split: its panes stay
    /// mounted underneath and must not take clicks or keystrokes.
    var isCovered: Bool {
        dependencies.dashboard.showsNewSession || dependencies.dashboard.showsRepositoryFinder
    }

    /// The shells running now, in a stable order so mounting one
    /// more never remounts the rest; internal accessors because the
    /// extension files cannot see the view's own state.
    var runningShellPaths: [String] {
        runningShells.sorted()
    }

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
        // Pushes and rebases poke this counter so their counts show
        // in the sidebar immediately rather than on the next poll.
        .onChange(of: dashboardRefreshRequest) {
            Task { await dependencies.dashboard.refresh() }
        }
        // A destroyed worktree takes its shell with it; a worktree
        // the sidebar merely stopped listing keeps its row, so
        // nothing else closes a shell pane behind the user's back.
        .onChange(of: dependencies.dashboard.worktreePaths) { _, paths in
            runningShells.formIntersection(paths)
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

    /// Whether a worktree's shell runs.
    func hasRunningShell(at path: String) -> Bool {
        runningShells.contains(path)
    }

    /// Starts a worktree's shell by mounting its pane.
    func startShell(at path: String) {
        runningShells.insert(path)
    }

    /// Ends a worktree's shell instantly: unmounting the pane kills
    /// its PTY, even when the shell has wedged beyond Ctrl-D.
    func closeShell(at path: String) {
        runningShells.remove(path)
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

    /// The push and rebase actions' immediate-refresh signal.
    @AppStorage("dashboardRefreshRequest")
    private var dashboardRefreshRequest = 0

    /// Worktrees whose browser has been opened; it stays mounted so
    /// its page survives tab switches.
    @State private var visitedBrowsers: Set<String> = []

    /// Worktrees whose shell is running; started explicitly, removed
    /// when the shell process exits, is closed or its worktree is
    /// destroyed, so the start button returns. Shells are plain
    /// local processes, so nothing persists across launches.
    @State private var runningShells: Set<String> = []

    /// Each worktree's last utility tab, persisted as
    /// path-tab-name lines so panes stay per-worktree.
    @AppStorage("worktreeTabs")
    private var worktreeTabs = ""
    @State private var rememberedTabs: [String: String] = [:]

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

    /// The middle pages, never sheets, cover the split rather than
    /// replacing it: unmounting the split takes its panes with it,
    /// and a pane can hold a running shell, which only destroying
    /// its worktree should end.
    private var detail: some View {
        ZStack {
            if let item = dependencies.dashboard.selection {
                split(for: item)
                    .opacity(isCovered ? 0 : 1)
                    .allowsHitTesting(isCovered == false)
            } else if isCovered == false {
                ContentUnavailableView(
                    "No worktree selected",
                    systemImage: "rectangle.stack",
                    description: Text("Pick a worktree on the left or create a session."),
                )
            }
            if dependencies.dashboard.showsNewSession {
                NewSessionPane(model: dependencies.dashboard)
            } else if dependencies.dashboard.showsRepositoryFinder {
                RepositoryFinderPane(model: dependencies.dashboard)
            }
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
            utilityHeader(for: item)
            Divider()
            utilityContent(for: item)
        }
        .task(id: item.worktree.path) {
            // A stale conversation focus must not survive switching
            // to another sidebar item.
            conversationWorktreePath = nil
            utilityTabName = rememberedTabs[item.worktree.path] ?? utilityTabName
        }
        .onChange(of: utilityTabName) {
            rememberedTabs[item.worktree.path] = utilityTabName
            worktreeTabs = rememberedTabs
                .map { $0.key + "\t" + $0.value }
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
        if item.isPlaceholder {
            // The row exists before the worktree does.
            ProgressView("Creating worktree and starting the agent…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isAutoResuming, item.session == nil {
            ProgressView("Resuming conversation…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let session = item.session {
            agentTerminal(for: session, isActive: isCovered == false)
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
            ) { await sessionStarted() }
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

    /// A running shell stays mounted whichever tab, worktree or page
    /// shows, so its terminal survives everything short of destroying
    /// the worktree it runs in. Both layers always fill the pane, so
    /// switches never resize a hidden terminal; a resize would make
    /// the shell reprint its prompt, which reads as stray newlines.
    /// Shells start only from their button, and a quit shell (Ctrl-D)
    /// returns to it.
    private func utilityContent(for item: WorktreeItem) -> some View {
        let showsShell = utilityTab == .shell
        let showsBrowser = utilityTab == .browser
        let path = item.worktree.path
        return ZStack {
            shellLayers(for: item)
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
        .task(id: item.id + utilityTabName) {
            if utilityTab == .browser {
                visitedBrowsers.insert(path)
            }
        }
    }
}
