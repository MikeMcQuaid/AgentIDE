import AgentIDEDomain
import DashboardFeature
import SwiftUI

// MARK: - RootView

/// The main window: the dashboard sidebar on the left; on the right,
/// segmented controls selecting the worktree's sessions over a split
/// of the sandboxed agent and a collapsible utility pane.
struct RootView: View {
    // MARK: Internal

    /// The utility header row's height: the tab capsules plus the
    /// row's padding. The floating toggle centres in this height and
    /// stripless pages inset their headers by it, clear of the
    /// titlebar band and that toggle.
    static let toggleRowHeight: CGFloat = 30

    let dependencies: AppDependencies

    /// Persisted as the tab's name rather than an index, so
    /// reordering the tabs can never repoint a saved selection;
    /// internal so the extension file can read it.
    @AppStorage("utilityTab")
    var utilityTabName = UtilityTab.review.rawValue

    /// Internal so the extension file's toggle button can drive it.
    @AppStorage("showsUtilityPane")
    var showsUtilityPane = true

    /// The worktree whose conversation is being resumed, so its pane
    /// shows the resume's progress rather than a terminal bound to
    /// the pane the resume is replacing; internal and settable
    /// because the extension files cannot see the view's own state.
    var resumingWorktree: String? {
        get { resumingIn }
        nonmutating set { resumingIn = newValue }
    }

    /// Whether the utility pane is both wanted and able to fit: a
    /// window too narrow for three panes shows the two the work
    /// happens in, without forgetting the pane was asked for.
    var showsUtility: Bool {
        PaneLayout(
            width: windowWidth,
            sidebar: sidebarWidth,
            utility: utilityPaneWidth,
            showsUtility: showsUtilityPane,
        ).showsUtility
    }

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

    /// The worktree whose conversation the review surfaces follow,
    /// and the browsers already opened; internal accessors because
    /// the extension files cannot see the view's own state.
    var conversationWorktree: String? {
        conversationWorktreePath
    }

    var visitedBrowserPaths: [String] {
        visitedBrowsers.sorted()
    }

    /// The worktree showing its new session form rather than its
    /// conversations, which is how a worktree that already has
    /// conversations starts a fresh session; internal and settable
    /// because the extension files that build those panes cannot
    /// see the view's own state.
    var startingSession: String? {
        get { startingIn }
        nonmutating set { startingIn = newValue }
    }

    var body: some View {
        // Plain panes with our own dividers: the navigation split
        // view's floating toggle covered nearby controls and split
        // views neither persisted divider positions nor honoured
        // ideal widths on this OS. The sidebar never hides; it
        // resizes down to a slim strip instead.
        // The window's width decides what the panes may be: widths
        // dragged on a large display do not fit a small one, and a
        // window whose display was unplugged lands on whatever is
        // left.
        HStack(spacing: 0) {
            DashboardView(model: dependencies.dashboard)
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarMaterial())
                .ignoresSafeArea(.container, edges: .top)
            PaneDivider(width: $sidebarWidth, range: PaneLayout.sidebarRange, controlsLeadingPane: true)
                .ignoresSafeArea(.container, edges: .top)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fitPanes(to: $0) }
        .sheet(isPresented: sessionManagerBinding) { sessionManager }
        .task {
            FlavourIcon.apply()
            finderFocusRequest = 0
            rememberedTabs = Self.decodeTabs(worktreeTabs)
            await dependencies.dashboard.poll()
        }
        // A shell command waiting on an editor is stopped until this
        // window shows it the file, so it is watched for separately
        // from the dashboard's own slower poll.
        .task {
            await waiting.watch(service: dependencies.service, dashboard: dependencies.dashboard)
        }
        // Sleep sometimes kills the sandbox herdr server; sessions
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
        // A destroyed worktree takes its shell and browser page with
        // it; a worktree the sidebar merely stopped listing keeps its
        // row, so nothing else closes a pane behind the user's back.
        .onChange(of: dependencies.dashboard.worktreePaths) { _, paths in
            runningShells.formIntersection(paths)
            visitedBrowsers.formIntersection(paths)
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
            resumingWorktree = item.worktree.path
            Task { await resumeLatest(in: item) }
        }
    }

    /// The file a command is waiting on in a worktree, which its
    /// editor pane shows instead of the finder.
    func waitingEdit(in worktreePath: String) -> ExternalEdit? {
        waiting.edit(in: worktreePath)
    }

    /// Dealing with a waiting file puts the pane back where it was,
    /// which is nearly always the shell the command was typed in.
    func finishedWaitingEdit() {
        waiting.restorePreviousPane()
    }

    func visitBrowser(at path: String) {
        visitedBrowsers.insert(path)
    }

    /// Closes a browser page: unmounting the pane ends the web
    /// process it costs, and the address stays remembered so opening
    /// the tab again brings the page back.
    func closeBrowser(at path: String) {
        visitedBrowsers.remove(path)
    }

    /// Points the review surfaces at the conversation picked on a
    /// repository page, so clicking around retargets Review and PRs.
    func focusConversation(at path: String?) {
        conversationWorktreePath = path
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
    private static let stripSpacing: CGFloat = 4

    /// The selected conversation's worktree on the repository page,
    /// nil when none exists; the review surfaces follow it. Internal
    /// so the extension file's tabs can read it.
    @State private var startingIn: String?

    @State private var conversationWorktreePath: String?

    /// Whether the launch's one automatic resume has run, so later
    /// selection changes never launch anything by themselves.
    @State private var hasAutoResumed = false

    /// Fills the primary pane with progress while the launch resume
    /// runs, instead of flashing the conversation list first.
    @State private var resumingIn: String?

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

    /// The files commands are waiting on, which take the utility
    /// pane over until they are dealt with.
    @State private var waiting: WaitingEdits = .init()

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

    /// What the window is now, which the panes are fitted to.
    @State private var windowWidth: CGFloat = 0

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
                if showsUtility == false {
                    utilityToggleButton
                        .frame(height: Self.toggleRowHeight)
                        .padding(.trailing, Self.stripSpacing)
                }
            }
            .frame(
                minWidth: PaneLayout.primaryMinimum,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top,
            )
            .ignoresSafeArea(.container, edges: .top)
            if showsUtility {
                PaneDivider(width: $utilityPaneWidth, range: PaneLayout.utilityRange, controlsLeadingPane: false)
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

    /// Narrows the panes to what the window can hold. The widths
    /// are written back, so the dividers keep dragging from where
    /// the panes actually are.
    private func fitPanes(to width: CGFloat) {
        windowWidth = width
        let layout = PaneLayout(
            width: width,
            sidebar: sidebarWidth,
            utility: utilityPaneWidth,
            showsUtility: showsUtilityPane,
        )
        if layout.sidebar != sidebarWidth {
            sidebarWidth = layout.sidebar
        }
        if layout.utility != utilityPaneWidth {
            utilityPaneWidth = layout.utility
        }
    }
}
