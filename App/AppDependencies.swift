import AgentIDEData
import AgentIDEDomain
import DashboardFeature
import TerminalUI

/// Builds every adapter once and hands them to the features; the
/// app's only wiring.
@MainActor
final class AppDependencies {
    // MARK: Lifecycle

    init() {
        defer { Self.shared = self }
        let roots = PlatformRoots.detect()
        PerformanceLog.sharedTemporaryDirectory = roots.sharedTemporaryDirectory
        let paths = WorkspacePaths.current()
        let runner = FoundationProcessRunner()
        let gitClient = GitClient(runner: runner)
        let githubClient = GitHubClient(runner: runner)
        let metadataStore = MetadataStore(file: paths.metadataFile)
        let launchProgress = LaunchProgress()
        let launcher = SandvaultLauncher(hostUser: paths.hostUser)
        let power: any PowerObserving = IOKitPower()
        let herdr = HerdrClient(
            runner: runner,
            launcher: launcher,
            isInsideSandbox: WorkspacePaths.isInsideSandbox,
            progress: launchProgress.reporter,
        )
        let sessionService = SessionService(
            paths: paths,
            git: gitClient,
            herdr: herdr,
            github: githubClient,
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: metadataStore,
            runners: [ClaudeCodeRunner(), CodexRunner()],
            launcher: launcher,
            summariser: FoundationModelClient(),
            progress: launchProgress.reporter,
        )
        git = gitClient
        github = githubClient
        service = sessionService
        store = metadataStore
        dashboard = DashboardModel(
            service: sessionService,
            store: metadataStore,
            github: githubClient,
            launchProgress: launchProgress,
        )
        // The machine's own power state, wired here rather than read
        // by the model, so the model under test is always plugged in.
        dashboard.isOnBattery = { power.isOnBattery }
        // Off the launch path: installing hooks writes into the
        // shared workspace and nothing about the first paint needs
        // it done first.
        let installer = HookInstaller(paths: paths)
        Task.detached(priority: .utility) {
            try? installer.ensureInstalled()
        }
    }

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Internal

    /// The one instance, for the App Intents, which the system
    /// invokes outside any view: nil only before the app has built
    /// itself.
    private(set) static var shared: AppDependencies?

    /// Watches whether the machine has a route out at all, so
    /// GitHub work waits rather than failing per branch per poll.
    /// The shared one, which every network call in the app reads.
    let network: NetworkMonitor = .shared

    let git: GitClient
    let github: GitHubClient
    let service: SessionService
    let dashboard: DashboardModel
    let store: MetadataStore
}
