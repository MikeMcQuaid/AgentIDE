import AgentIDEData
import AgentIDEDomain
import Foundation
import Synchronization
import Testing

// MARK: - FileListingTests

/// The fuzzy finder's file listing, whose concurrent callers must
/// share one ripgrep run: the centre and side editors mount
/// together.
struct FileListingTests {
    @Test
    func `concurrent file listings share one ripgrep run`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let runner = SlowCountingRunner(standardOutput: "one.swift\ntwo.swift\n")
        let service = SessionService(
            paths: world.paths,
            git: GitClient(runner: runner),
            herdr: world.herdr,
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: world.paths.eventsDirectory),
            store: MetadataStore(file: world.paths.metadataFile),
            runners: [],
            processes: runner,
        )

        async let first = service.listFiles(worktreePath: world.repository.path)
        async let second = service.listFiles(worktreePath: world.repository.path)
        let listings = await [first, second]
        #expect(listings[0] == ["one.swift", "two.swift"])
        #expect(listings[1] == listings[0])
        #expect(runner.runCount == 1)

        // A listing after the shared one finished reads afresh.
        _ = await service.listFiles(worktreePath: world.repository.path)
        #expect(runner.runCount == 2)
    }

    @Test
    func `search finds matches with ripgrep`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let target = world.repository.path + "/needle.swift"
        try "let haystack = 1\nlet needleValue = 2\n".write(toFile: target, atomically: true, encoding: .utf8)

        let hits = await world.service.search(worktreePath: world.repository.path, query: "needleValue")
        let hit = try #require(hits.first)
        #expect(hit.file == "needle.swift")
        #expect(hit.line == 2)
        #expect(hit.text.contains("needleValue"))
        #expect(await world.service.search(worktreePath: world.repository.path, query: "").isEmpty)

        // Hidden files are part of the project (workflows, dot
        // configurations) and search like any other.
        try "hiddenNeedle here\n".write(
            toFile: world.repository.path + "/.hidden.yml",
            atomically: true,
            encoding: .utf8,
        )
        let hidden = await world.service.search(worktreePath: world.repository.path, query: "hiddenNeedle")
        #expect(hidden.first?.file == ".hidden.yml")
    }

    @Test
    func `lists files for the fuzzy finder`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try FileManager.default.createDirectory(
            atPath: world.repository.path + "/deep",
            withIntermediateDirectories: true,
        )
        try "x\n".write(toFile: world.repository.path + "/deep/nested.swift", atomically: true, encoding: .utf8)

        let files = await world.service.listFiles(worktreePath: world.repository.path)
        #expect(files.contains("deep/nested.swift"))
        #expect(files.contains("README.md"))

        // Hidden files list too; git's own machinery never does.
        try FileManager.default.createDirectory(
            atPath: world.repository.path + "/.github/workflows",
            withIntermediateDirectories: true,
        )
        try "on: push\n".write(
            toFile: world.repository.path + "/.github/workflows/ci.yml",
            atomically: true,
            encoding: .utf8,
        )
        let withHidden = await world.service.listFiles(worktreePath: world.repository.path)
        #expect(withHidden.contains(".github/workflows/ci.yml"))
        #expect(withHidden.contains { $0.hasPrefix(".git/") } == false)
    }
}

// MARK: - RepositoryPageIntegrationTests

/// The repository page's conversation browser and unread state, which
/// span worktrees rather than one session.
struct RepositoryPageIntegrationTests {}

// MARK: - SlowCountingRunner

/// Answers fixed output slowly enough that concurrent callers
/// overlap, counting how many commands actually ran.
private final class SlowCountingRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(standardOutput: String) {
        self.standardOutput = standardOutput
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    var runCount: Int {
        count.withLock { $0 }
    }

    func run(
        _: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) async throws -> ProcessResult {
        count.withLock { $0 += 1 }
        try await Task.sleep(for: .milliseconds(Self.stallMilliseconds))
        return ProcessResult(status: 0, standardOutput: standardOutput, standardError: "")
    }

    // MARK: Private

    /// Long enough that both callers overlap on any scheduler.
    private static let stallMilliseconds = 200

    private let count: Mutex<Int> = .init(0)
    private let standardOutput: String
}
