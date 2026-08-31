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
}

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
