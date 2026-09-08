import AgentIDEData
@testable import DashboardFeature
import Foundation
import Testing

/// A reading that asks for a reading must not wait for one: the one
/// it is inside is waiting for it.
@MainActor
struct RefreshReentryTests {
    // MARK: Internal

    @Test
    func `a refresh asked for from inside the reading does not wait on it`() async {
        let model = makeModel()
        // A reading is in flight and will be for a while.
        let reading = Task { _ = try? await Task.sleep(for: .seconds(30)) }
        model.refreshTask = reading
        defer { reading.cancel() }

        // Cleaning up after a merge asked for a reading from inside
        // the reading that found the merge; each waited on the
        // other until the app was restarted.
        let returned = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let caller = withUnsafeCurrentTask { $0?.hashValue }
                await MainActor.run { model.readingTaskID = caller }
                await model.refresh()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(returned)
        #expect(model.followUpDue)
    }

    // MARK: Private

    /// A model over a throwaway workspace; nothing is read from it.
    private func makeModel() -> DashboardModel {
        let runner = FoundationProcessRunner()
        let base = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-dashboard-" + UUID().uuidString, isDirectory: true)
            .path
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: base + "/shared",
            sandboxHome: base + "/home",
            metadataFile: base + "/state.json",
        )
        let service = SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                configHome: base + "/herdr",
            ),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: MetadataStore(file: paths.metadataFile),
            runners: [],
        )
        return DashboardModel(
            service: service,
            store: MetadataStore(file: paths.metadataFile),
            github: GitHubClient(runner: runner),
        )
    }
}
