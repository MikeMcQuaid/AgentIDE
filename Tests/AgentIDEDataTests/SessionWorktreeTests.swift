@testable import AgentIDEData
import Foundation
import Testing

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

    @Test(arguments: [nil, -3_601, -1_800, -30] as [TimeInterval?])
    func `new worktrees use origin and refresh only after an hour`(fetchAge: TimeInterval?) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = world.repository
        let origin = world.root + "/origin"
        try await TestSupport.makeRepository(at: origin)
        try await TestSupport.runGit(["branch", "--move", "main", "trunk"], in: origin)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: repository.path)
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
