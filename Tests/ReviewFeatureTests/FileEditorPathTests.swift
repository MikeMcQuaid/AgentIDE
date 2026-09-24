import AgentIDEData
import Foundation
@testable import ReviewFeature
import Testing

struct FileEditorPathTests {
    @Test
    func `absolute files open outside the worktree but relative escapes are refused`() {
        let root = FileManager.default.currentDirectoryPath + "/.test-scratch/editor-path-" + UUID().uuidString
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root,
            sandboxHome: root + "/home",
            metadataFile: root + "/state.json",
        )
        let runner = FoundationProcessRunner()
        let service = SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                configHome: root + "/herdr",
            ),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: MetadataStore(file: paths.metadataFile),
            runners: [],
        )
        for (file, expected) in [
            (root + "/prompt.md", root + "/prompt.md"),
            ("file.swift", root + "/repo/file.swift"),
            ("Sources/../file.swift", root + "/repo/file.swift"),
            ("../prompt.md", nil),
            ("../repository/file.swift", nil),
        ] {
            let view = FileEditorView(worktreePath: root + "/repo", relativePath: file, service: service)
            #expect(view.path == expected)
        }
    }
}
