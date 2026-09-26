import AgentIDEData
import AppKit
@testable import ReviewFeature
import SwiftUI
import Testing

@MainActor
struct EditorPaneStateTests {
    // MARK: Internal

    @Test
    func `saved files stay with their worktree and closing overrides the legacy file`() throws {
        let suite = "EditorPaneStateTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let role = EditorPane.Role.utility
        defaults.set("old.swift", forKey: role.key("editorFilePath"))
        defaults.set("/first", forKey: role.key("editorFileWorktree"))
        #expect(role.file(in: "/first", defaults: defaults) == "old.swift")
        #expect(role.file(in: "/second", defaults: defaults) == nil)
        #expect(role.other.file(in: "/first", defaults: defaults) == nil)

        defaults.set("other.swift", forKey: role.key("editorFilePath", worktreePath: "/second"))
        defaults.set("", forKey: role.key("editorFilePath", worktreePath: "/first"))
        #expect(role.file(in: "/first", defaults: defaults)?.isEmpty == true)
        #expect(role.file(in: "/second", defaults: defaults) == "other.swift")
    }

    @Test(arguments: EditorPane.Role.allCases)
    func `switching worktrees restores their files and scroll positions`(role: EditorPane.Role) async throws {
        let fixture = try Fixture(role: role)
        defer { fixture.close() }
        fixture.open(in: "first", line: 3)
        let first = try await fixture.editor(in: "first")
        let scroll = try #require(first.enclosingScrollView)
        let layout = try #require(unsafe first.layoutManager)
        try layout.ensureLayout(for: #require(unsafe first.textContainer))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)
        let origin = scroll.contentView.bounds.origin
        try #require(origin.y > 0)

        fixture.open(in: "second", line: 7)
        _ = try await fixture.editor(in: "second")
        fixture.show("first")
        let restored = try await fixture.editor(in: "first")
        for _ in 0 ..< 100 where restored.enclosingScrollView?.contentView.bounds.origin != origin {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(restored.enclosingScrollView?.contentView.bounds.origin == origin)
        fixture.show("second")
        _ = try await fixture.editor(in: "second")
    }

    // MARK: Private

    private struct Fixture {
        // MARK: Lifecycle

        init(role: EditorPane.Role) throws {
            self.role = role
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.currentDirectoryPath + "/.test-scratch/" + suite
            for name in ["first", "second"] {
                try FileManager.default.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
                try (0 ..< 200)
                    .lazy
                    .map { name + " line " + String($0) }
                    .joined(separator: "\n")
                    .write(toFile: root + "/" + name + "/file.txt", atomically: true, encoding: .utf8)
            }
            let paths = WorkspacePaths(
                hostUser: "test",
                sharedWorkspace: root,
                sandboxHome: root + "/home",
                metadataFile: root + "/state.json",
            )
            let runner = EmptyRunner()
            service = SessionService(
                paths: paths,
                git: GitClient(runner: runner),
                herdr: HerdrClient(
                    runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true,
                ),
                github: GitHubClient(runner: runner),
                transcripts: TranscriptReader(),
                spool: EventSpool(directory: paths.eventsDirectory),
                store: MetadataStore(file: paths.metadataFile),
                runners: [],
                processes: runner,
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        // MARK: Internal

        let suite = "EditorPaneStateTests-" + UUID().uuidString
        let root: String
        let defaults: UserDefaults
        let role: EditorPane.Role
        let service: SessionService
        let host: NSHostingView = .init(rootView: AnyView(EmptyView()))
        let window: NSWindow = .init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )

        func open(in name: String, line: Int) {
            defaults.set("file.txt", forKey: role.key("editorFilePath", worktreePath: root + "/" + name))
            defaults.set(line, forKey: role.key("editorFileLine", worktreePath: root + "/" + name))
            defaults.set(
                defaults.integer(forKey: role.key("editorFileRequest")) + 1,
                forKey: role.key("editorFileRequest"),
            )
            show(name)
        }

        func show(_ name: String) {
            host.rootView = AnyView(EditorPane(worktreePath: root + "/" + name, service: service, role: role)
                // Matches the identity applied by RootView.editorPane.
                .id(root + "/" + name)
                .defaultAppStorage(defaults))
            host.layoutSubtreeIfNeeded()
        }

        func editor(in name: String) async throws -> EditingTextView {
            for _ in 0 ..< 100 {
                host.layoutSubtreeIfNeeded()
                if let view = Self.editor(in: host), view.string.hasPrefix(name) {
                    return view
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            let view = try #require(Self.editor(in: host), "The worktree's open file should be restored")
            try #require(view.string.hasPrefix(name))
            return view
        }

        func close() {
            host.rootView = AnyView(EmptyView())
            window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(atPath: root)
        }

        // MARK: Private

        private static func editor(in view: NSView) -> EditingTextView? {
            (view as? EditingTextView) ?? view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
    }

    private struct EmptyRunner: ProcessRunner {
        func run(
            _: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
        ) -> ProcessResult {
            ProcessResult(status: 0, standardOutput: "", standardError: "")
        }
    }
}
