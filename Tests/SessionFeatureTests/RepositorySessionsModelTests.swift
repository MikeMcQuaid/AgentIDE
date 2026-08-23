import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import SessionFeature
import Testing

/// Exercises the conversations model's listing, titles, locations
/// and resume shapes through its seams, so the pane's behaviour
/// tests without transcripts on disk or a window.
struct RepositorySessionsModelTests {
    // MARK: Internal

    @Test
    func `loading lists newest first and selects the first conversation`() async {
        let model = makeModel()
        model.listSessions = {
            [
                (session("new", title: "Newest", modifiedAt: 2), "/worktrees/one"),
                (session("old", title: "Oldest", modifiedAt: 1), "/worktrees/two"),
            ]
        }
        await model.load()
        #expect(model.hasLoaded)
        #expect(model.sessions.map(\.session.id) == ["new", "old"])
        #expect(model.selected?.id == "new")
    }

    @Test
    func `a worktree scope filters the listing to that worktree`() async {
        let model = makeModel(worktreePath: "/worktrees/two")
        model.listSessions = {
            [
                (session("a", title: "One", modifiedAt: 2), "/worktrees/one"),
                (session("b", title: "Two", modifiedAt: 1), "/worktrees/two"),
            ]
        }
        await model.load()
        #expect(model.sessions.map(\.session.id) == ["b"])
    }

    @Test
    func `untitled conversations borrow their worktree's name`() {
        let model = makeModel()
        let untitled = (session: session("u", title: "", modifiedAt: 1), worktreePath: "/worktrees/fix_crash")
        #expect(model.title(of: untitled) == "fix_crash")
        let titled = (session: session("t", title: "Fix the crash", modifiedAt: 1), worktreePath: "/worktrees/x")
        #expect(model.title(of: titled) == "Fix the crash")
    }

    @Test
    func `locations shorten to their tail and mark deleted worktrees`() {
        let model = makeModel()
        model.fileExists = { $0 == "/deep/path/kept" }
        #expect(model.location(of: "/deep/path/kept") == "path/kept")
        #expect(model.location(of: "/deep/path/gone") == "path/gone (deleted)")
    }

    @Test
    func `resuming here needs the worktree to still exist`() async {
        let model = makeModel()
        model.listSessions = { [(session("a", title: "One", modifiedAt: 1), "/worktrees/gone")] }
        model.fileExists = { _ in false }
        await model.load()
        #expect(model.selected != nil)
        #expect(model.selectedWorktreePath == nil)

        model.fileExists = { _ in true }
        #expect(model.selectedWorktreePath == "/worktrees/gone")
    }

    @Test
    func `a here-resume names its branch after the path's last component`() {
        let worktree = makeModel().resumeWorktree(at: "/worktrees/uuid/fix_crash")
        #expect(worktree.branch == "fix_crash")
        #expect(worktree.path == "/worktrees/uuid/fix_crash")
        #expect(worktree.repositoryName == "repo")
    }

    // MARK: Private

    /// A model whose listing and file checks are replaced; the
    /// service is never reached by these tests.
    private func makeModel(worktreePath: String? = nil) -> RepositorySessionsModel {
        let runner = FoundationProcessRunner()
        let base = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-sessionsmodel-" + UUID().uuidString, isDirectory: true)
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
        let model = RepositorySessionsModel(
            repository: Repository(name: "repo", path: "/repo"),
            service: service,
            worktreePath: worktreePath,
        )
        model.listSessions = { [] }
        model.fileExists = { _ in true }
        return model
    }

    private func session(_ id: String, title: String, modifiedAt: Int) -> TranscriptSession {
        TranscriptSession(
            id: id,
            path: "/transcripts/" + id + ".jsonl",
            agent: .claudeCode,
            modifiedAt: modifiedAt,
            title: title,
        )
    }
}
