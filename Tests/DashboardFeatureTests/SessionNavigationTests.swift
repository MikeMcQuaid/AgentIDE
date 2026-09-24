import AgentIDEData
import AgentIDEDomain
import AppKit
@testable import DashboardFeature
import SwiftUI
import Synchronization
import Testing

@Suite(.serialized)
struct SessionNavigationTests {
    // MARK: Internal

    @Test
    func `a failed agent wait backs off and cancellation stops it`() async throws {
        let runner = FailedWaitRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close(); fixture.model.watchAgentStates([]) }
        fixture.model.groups[0].items[0] = WorktreeItem(
            worktree: fixture.model.groups[0].items[0].worktree,
            session: AgentSession(name: "session", agent: .claudeCode, status: .running, paneID: "pane"),
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        fixture.model.watchAgentStates(fixture.model.groups)
        let watcher = try #require(fixture.model.agentWatchers["pane"])
        for _ in 0 ..< 50 where runner.calls.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(runner.calls.withLock { $0 } == 1)
        watcher.cancel()
        await watcher.value
        #expect(runner.calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["First prompt", "The next prompt, typed while the first starts"])
    func `a completed launch clears only its own prompt`(nextPrompt: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let defaults = UserDefaults.standard
        let keys = ["newSessionPrompt", "agentKind", "agentModel", "agentEffort"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set("First", forKey: "newSessionPrompt")
        defaults.set("claude", forKey: "agentKind")
        defaults.set("sonnet", forKey: "agentModel")
        defaults.set("high", forKey: "agentEffort")
        var submitted: String?
        var finish: CheckedContinuation<Void, Never>?
        let form = AgentSessionForm(
            model: fixture.model,
            repository: fixture.repository,
            submitTitle: "Start agent",
            submitHelp: "Start",
        ) { submission in
            submitted = submission.prompt
            await withCheckedContinuation { finish = $0 }
        }
        let host = NSHostingView(rootView: AnyView(form))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { finish?.resume(); window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try fixture.typeAndSubmit(in: host, windowNumber: window.windowNumber)
        for _ in 0 ..< 50 where submitted == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(submitted == "First prompt")

        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        defaults.set(nextPrompt, forKey: "newSessionPrompt")
        try await Task.sleep(for: .milliseconds(50))
        finish?.resume()
        finish = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(defaults.string(forKey: "newSessionPrompt") == (nextPrompt == "First prompt" ? "" : nextPrompt))
    }

    @Test
    func `explicit navigation reveals a collapsed repository even when already selected`() {
        let fixture = Fixture()
        defer { fixture.close() }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "collapsedRepositories")
        defer { defaults.set(previous, forKey: "collapsedRepositories") }
        let item = fixture.model.groups[0].items[0]
        fixture.model.selection = item
        defaults.set(fixture.repository.path + "\n/another", forKey: "collapsedRepositories")

        fixture.model.openNewSession(for: fixture.repository)
        #expect(defaults.string(forKey: "collapsedRepositories") == "/another")
        #expect(fixture.model.showsNewSession)

        defaults.set(fixture.repository.path + "\n/another", forKey: "collapsedRepositories")
        fixture.model.select(item)
        #expect(defaults.string(forKey: "collapsedRepositories") == "/another")
        #expect(fixture.model.showsNewSession == false)

        defaults.set(fixture.repository.path, forKey: "collapsedRepositories")
        fixture.model.selection = item
        #expect(defaults.string(forKey: "collapsedRepositories") == fixture.repository.path)
    }

    @Test
    func `selecting an adopted worktree reveals the repository that lists it`() {
        let fixture = Fixture()
        defer { fixture.close() }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "collapsedRepositories")
        defer { defaults.set(previous, forKey: "collapsedRepositories") }
        let item = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: fixture.root + "/worktrees/repo/.base",
                branch: "adopted",
                path: fixture.root + "/worktrees/repo/adopted",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        fixture.model.groups[0].items.append(item)
        defaults.set(fixture.repository.path + "\n/another", forKey: "collapsedRepositories")

        fixture.model.select(item)
        #expect(defaults.string(forKey: "collapsedRepositories") == "/another")
    }

    // MARK: Private

    private struct Fixture {
        // MARK: Lifecycle

        init(runner: any ProcessRunner = EmptyRunner()) {
            let paths = WorkspacePaths(
                hostUser: "test",
                sharedWorkspace: root + "/shared",
                sandboxHome: root + "/home",
                metadataFile: root + "/state.json",
            )
            let store = MetadataStore(file: paths.metadataFile)
            let github = GitHubClient(runner: runner)
            let service = SessionService(
                paths: paths,
                git: GitClient(runner: runner),
                herdr: HerdrClient(
                    runner: runner,
                    launcher: SandvaultLauncher(hostUser: "test"),
                    isInsideSandbox: true,
                    configHome: root + "/herdr",
                ),
                github: github,
                transcripts: TranscriptReader(),
                spool: EventSpool(directory: paths.eventsDirectory),
                store: store,
                runners: [],
            )
            model = DashboardModel(service: service, store: store, github: github)
            repository = Repository(name: "repo", path: paths.repositoriesDirectory + "/repo")
            let item = WorktreeItem(
                worktree: Worktree(
                    repositoryName: repository.name,
                    repositoryPath: repository.path,
                    branch: "main",
                    path: repository.path,
                ),
                session: nil,
                isDirty: false,
                aheadOfUpstream: nil,
                hasUnread: false,
            )
            model.groups = [RepositoryGroup(repository: repository, items: [item])]
        }

        // MARK: Internal

        let root = FileManager.default.currentDirectoryPath + "/.test-scratch/navigation-" + UUID().uuidString
        let model: DashboardModel
        let repository: Repository

        func typeAndSubmit(in host: NSView, windowNumber: Int) throws {
            let editor = try #require(textView(in: host))
            editor.insertText(" prompt", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 1,
                windowNumber: windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36,
            ))
            #expect(host.performKeyEquivalent(with: key))
        }

        func close() {
            try? FileManager.default.removeItem(atPath: root)
        }

        // MARK: Private

        private func textView(in view: NSView) -> NSTextView? {
            (view as? NSTextView) ?? view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
    }

    private struct EmptyRunner: ProcessRunner {
        @concurrent
        func run(
            _: [String],
            workingDirectory _: String?,
            environment _: [String: String],
            outputLimit _: Int?,
        ) async -> ProcessResult {
            ProcessResult(status: 0, standardOutput: "[]", standardError: "")
        }
    }

    private final nonisolated class FailedWaitRunner: ProcessRunner {
        // MARK: Lifecycle

        deinit {
            // No resources to release.
        }

        // MARK: Internal

        let calls: Mutex<Int> = .init(0)

        @concurrent
        func run(
            _: [String],
            workingDirectory _: String?,
            environment _: [String: String],
            outputLimit _: Int?,
        ) async -> ProcessResult {
            calls.withLock { $0 += 1 }
            return ProcessResult(status: 1, standardOutput: "", standardError: "Pane is gone")
        }
    }
}
