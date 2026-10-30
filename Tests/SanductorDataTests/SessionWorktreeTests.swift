import Foundation
@testable import SanductorData
import Synchronization
import Testing

// MARK: - SessionWorktreeTests

struct SessionWorktreeTests {
    @Test
    func `a failed fetch leaves no worktree or successful fetch timestamp`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await TestSupport.runGit(
            ["remote", "add", "origin", world.root + "/missing"],
            in: world.repository.path,
        )

        await #expect(throws: CommandError.self) {
            try await world.service.createWorktreePath(repository: world.repository, branch: "new-session")
        }

        #expect(try await world.service.git.worktrees(of: world.repository).isEmpty)
        #expect(world.service.store.load().gitFetchedAt[world.repository.path] == nil)
    }

    @Test
    func `worktrees started together under one name get distinct branches`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        async let first = world.service.createWorktree(repository: world.repository, named: "same_work")
        async let second = world.service.createWorktree(repository: world.repository, named: "same_work")
        let branches = try await [first.branch, second.branch]

        #expect(Set(branches) == ["same_work", "same_work-2"])
    }

    @Test
    func `stale remotes asked for together are fetched once`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let origin = world.root + "/origin"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: world.repository.path)
        let runner = FetchCountingRunner()
        let service = world.service(herdr: world.herdr, git: GitClient(runner: runner))

        async let first: Void = service.fetchIfStale(repositoryPath: world.repository.path)
        async let second: Void = service.fetchIfStale(repositoryPath: world.repository.path)
        _ = try await (first, second)

        #expect(runner.fetches.withLock(\.self) == 1)
    }

    @Test(arguments: [nil, -3_601, -1_800, -30] as [TimeInterval?])
    func `new worktrees use origin and refresh only after an hour`(fetchAge: TimeInterval?) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = world.repository
        let origin = world.root + "/origin"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.runGit(["branch", "--move", "main", "trunk"], in: origin)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: repository.path)
        try await TestSupport.runGit(["remote", "add", "unused-fork", world.root + "/missing"], in: repository.path)
        try await TestSupport.runGit(["fetch", "origin"], in: repository.path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: repository.path)
        let cached = await world.service.git.commitHash(of: "origin/HEAD", worktreePath: repository.path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Upstream change"], in: origin)
        let latest = await world.service.git.commitHash(of: "HEAD", worktreePath: origin)
        try await TestSupport.runGit(["checkout", "-b", "local-work"], in: repository.path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Local work"], in: repository.path)
        let local = await world.service.git.commitHash(of: "HEAD", worktreePath: repository.path)
        let stamp = fetchAge.map { Date().addingTimeInterval($0) }
        world.service.store.update { $0.gitFetchedAt[repository.path] = stamp }

        let path = try await world.service.createWorktreePath(repository: repository, branch: "new-session")

        let shouldFetch = fetchAge == nil || (fetchAge ?? 0) < -3_600
        #expect(await world.service.git.commitHash(of: "HEAD", worktreePath: path) == (shouldFetch ? latest : cached))
        #expect(await world.service.git.commitHash(of: "HEAD", worktreePath: repository.path) == local)
        #expect(await world.service.git.currentBranch(worktreePath: repository.path) == "local-work")
        let upstream = try await TestSupport.runGit(
            ["for-each-ref", "--format=%(upstream)", "refs/heads/new-session"],
            in: path,
        )
        #expect(upstream.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if shouldFetch {
            #expect(try #require(world.service.store.load().gitFetchedAt[repository.path]) > (stamp ?? .distantPast))
        } else {
            #expect(world.service.store.load().gitFetchedAt[repository.path] == stamp)
        }
    }
}

// MARK: - FetchCountingRunner

/// Runs every command for real, counting the `git fetch`es.
private final class FetchCountingRunner: ProcessRunner {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    let fetches: Mutex<Int> = .init(0)

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.contains("fetch") {
            fetches.withLock { $0 += 1 }
        }
        return try await runner.run(
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            outputLimit: outputLimit,
        )
    }

    // MARK: Private

    private let runner: FoundationProcessRunner = .init()
}
