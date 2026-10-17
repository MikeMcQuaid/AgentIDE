@testable import AgentIDEData
import Foundation
import Testing

// MARK: - ForkRemoteConcurrencyTests

struct ForkRemoteConcurrencyTests {
    @Test(.timeLimit(.minutes(2)), arguments: [Duration.zero, .seconds(6)])
    func `adoption cannot race cleanup through another client or linked worktree`(delay: Duration) async throws {
        let root = try TestSupport.temporaryDirectory("remote-race")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        let fork = root + "/fork"
        let linked = root + "/linked"
        let alias = root + "/alias"
        let unrelated = root + "/unrelated"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.makeRepository(at: unrelated)
        try await TestSupport.runGit(["clone", "--bare", path, fork], in: root)
        try await TestSupport.runGit(["branch", "topic", "main"], in: fork)
        try await TestSupport.runGit(["worktree", "add", "--relative-paths", "-b", "topic", linked, "main"], in: path)
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: linked)
        let git = GitClient(runner: FoundationProcessRunner())
        try await git.adoptRemote(named: "contributor", url: fork, branch: "main", worktreePath: path)
        try await TestSupport.runGit(["config", "--remove-section", "branch.main"], in: path)

        let paused = PausedRemoteRunner(adoptionDelay: delay)
        let cleanup = Task {
            try await GitClient(runner: paused).removeUnusedForkRemotes(repositoryPath: path)
        }
        let reached = await TestSupport.poll { await paused.isPaused }
        #expect(reached)
        let adoption = Task {
            try await GitClient(runner: paused).adoptRemote(
                named: "contributor", url: fork, branch: "topic", worktreePath: alias,
            )
        }
        let independent = Task {
            try await GitClient(runner: paused).adoptRemote(
                named: "contributor", url: fork, branch: "main", worktreePath: unrelated,
            )
        }
        let independentResult = await withTaskCancellationHandler {
            await independent.result
        } onCancel: {
            Task {
                await paused.resume()
            }
        }
        let overlapped = await TestSupport.poll(timeout: 1) { await paused.adoptedPaths.contains(alias) }
        #expect(overlapped == false)
        await paused.resume()
        try await cleanup.value
        try await adoption.value
        try independentResult.get()
        #expect(await git.remoteURL(named: "contributor", worktreePath: path) == fork)
        #expect(await git.branchRemote(worktreePath: linked, branch: "topic") == "contributor")
    }

    @Test
    func `a failed adoption releases cleanup`() async throws {
        let path = try TestSupport.temporaryDirectory("remote-failure")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        await #expect(throws: CommandError.self) {
            try await git.adoptRemote(named: "contributor", url: path, branch: "missing", worktreePath: path)
        }
        try await git.removeUnusedForkRemotes(repositoryPath: path)
        #expect(await git.remoteURL(named: "contributor", worktreePath: path) == nil)
    }
}

// MARK: - PausedRemoteRunner

private actor PausedRemoteRunner: ProcessRunner {
    // MARK: Lifecycle

    init(adoptionDelay: Duration) {
        self.adoptionDelay = adoptionDelay
    }

    // MARK: Internal

    private(set) var adoptedPaths: Set<String> = []

    var isPaused: Bool {
        continuation != nil
    }

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        outputLimit: Int?,
    ) async throws -> ProcessResult {
        let result = try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
        if arguments.last == #"^(branch\..*\.(remote|pushremote)|remote\.pushdefault)$"# {
            await withCheckedContinuation { continuation = $0 }
        }
        if arguments.contains(where: { $0.hasSuffix(".pushremote") }), arguments.last == "contributor",
           let workingDirectory
        {
            if adoptedPaths.isEmpty {
                try await Task.sleep(for: adoptionDelay)
            }
            adoptedPaths.insert(workingDirectory)
        }
        return result
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    // MARK: Private

    private var continuation: CheckedContinuation<Void, Never>?
    private let adoptionDelay: Duration
}
