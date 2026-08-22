import AgentIDEData
import DashboardFeature
import TerminalUI

/// Builds every adapter once and hands them to the features; the
/// app's only wiring.
@MainActor
final class AppDependencies {
    // MARK: Lifecycle

    init() {
        let paths = WorkspacePaths.current()
        let runner = FoundationProcessRunner()
        let gitClient = GitClient(runner: runner)
        let githubClient = GitHubClient(runner: runner)
        let metadataStore = MetadataStore(file: paths.metadataFile)
        let launchProgress = LaunchProgress()
        let herdr = HerdrClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: paths.hostUser),
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
        try? HookInstaller(paths: paths).ensureInstalled()
    }

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Internal

    let git: GitClient
    let github: GitHubClient
    let service: SessionService
    let dashboard: DashboardModel
    let store: MetadataStore
}
