@testable import AgentIDEData
import Foundation
import Testing

extension BranchStackIntegrationTests {
    @Test(arguments: [false, true], [false, true])
    func `restacking uses the remote base and refreshes it after a stale failure`(
        localBaseMoved: Bool,
        staleRemote: Bool,
    ) async throws {
        let world = try await Self.staleBaseWorld()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = StackedSessionIntegrationTests.worktree("upper", at: path, in: world.repository)
        if staleRemote {
            try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "main"], in: path)
        }
        if localBaseMoved {
            try await TestSupport.runGit(["checkout", "main"], in: path)
            try await Self.commit("unpushed base work", in: path)
            try await TestSupport.runGit(["checkout", "upper"], in: path)
        }
        let base = try await Self.tip(of: "main", in: path)
        let tree = try await Self.tip(of: "upper^{tree}", in: path)

        #expect(try await world.service.restack(worktree: worktree) == ["lower", "upper"])

        #expect(try await Self.tip(of: "main", in: path) == base)
        #expect(try await Self.tip(of: "upper^{tree}", in: path) == tree)
        #expect(await world.service.git.isAncestor("origin/main", of: "lower", worktreePath: path))
        #expect(await world.service.git.commitCount(from: "origin/main", to: "lower", worktreePath: path) == 1)
        #expect(await world.service.git.commitCount(from: "lower", to: "upper", worktreePath: path) == 1)
        #expect(await world.service.git.allCommitsSigned(worktreePath: path, range: "origin/main..upper"))
        #expect(try await Self.branch(in: path) == "upper")
        #expect(await world.service.git.isDirty(worktreePath: path) == false)
    }

    @Test(arguments: [false, true])
    func `a genuine conflict restores the stack after refreshing the remote`(staleRemote: Bool) async throws {
        let world = try await Self.staleBaseWorld()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = StackedSessionIntegrationTests.worktree("upper", at: path, in: world.repository)
        try "conflicting remote work".write(
            toFile: world.root + "/origin/lower_work.txt", atomically: true, encoding: .utf8,
        )
        try await TestSupport.runGit(["add", "lower_work.txt"], in: world.root + "/origin")
        try await TestSupport.runGit(["commit", "-m", "Conflicting remote work"], in: world.root + "/origin")
        if staleRemote {
            try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "main"], in: path)
        } else {
            try await TestSupport.runGit(["fetch", "origin"], in: path)
        }
        let base = try await Self.tip(of: "main", in: path)
        let lower = try await Self.tip(of: "lower", in: path)
        let upper = try await Self.tip(of: "upper", in: path)

        let failure = await #expect(throws: (any Error).self) {
            try await world.service.restack(worktree: worktree)
        }

        #expect(failure?.localizedDescription.contains("Rebase onto refs/remotes/origin/main failed")
            == staleRemote)
        #expect(try await Self.tip(of: "main", in: path) == base)
        #expect(try await Self.tip(of: "lower", in: path) == lower)
        #expect(try await Self.tip(of: "upper", in: path) == upper)
        #expect(try await Self.branch(in: path) == "upper")
        #expect(await world.service.git.isDirty(worktreePath: path) == false)
    }

    @Test
    func `the rebase button follows the remote base even when signed branches contain local main`() async throws {
        let world = try await Self.staleBaseWorld()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = StackedSessionIntegrationTests.worktree("upper", at: path, in: world.repository)
        _ = try await world.service.restack(worktree: worktree)
        #expect(await world.service.stackFacts(for: worktree).outOfPlace.isEmpty)
        try await Self.commit("new upstream work", in: world.root + "/origin")
        try await TestSupport.runGit(["fetch", "origin"], in: path)

        #expect(await world.service.stackFacts(for: worktree).outOfPlace == ["lower"])
        #expect(try await world.service.restack(worktree: worktree) == ["lower", "upper"])

        #expect(await world.service.git.isAncestor("origin/main", of: "lower", worktreePath: path))
        #expect(await world.service.stackFacts(for: worktree).outOfPlace.isEmpty)
    }

    @Test
    func `restacking refreshes a cached stack after fetching a merged parent`() async throws {
        let world = try await Self.staleBaseWorld()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = StackedSessionIntegrationTests.worktree("upper", at: path, in: world.repository)
        #expect(await world.service.stack(for: worktree).branches == ["lower", "upper"])
        let lower = try await Self.tip(of: "lower", in: path)
        try await TestSupport.runGit(["fetch", "origin", "lower"], in: world.root + "/origin")
        try await TestSupport.runGit(["merge", "--ff-only", "FETCH_HEAD"], in: world.root + "/origin")
        world.service.store.update { $0.gitFetchedAt[path] = nil }

        #expect(try await world.service.restack(worktree: worktree) == ["upper"])

        #expect(try await Self.tip(of: "lower", in: path) == lower)
        #expect(await world.service.git.isAncestor("origin/main", of: "upper", worktreePath: path))
        #expect(await world.service.git.commitCount(from: "origin/main", to: "upper", worktreePath: path) == 1)
        #expect(try await Self.branch(in: path) == "upper")
    }

    private static func staleBaseWorld() async throws -> World {
        let world = try await World.make()
        let path = world.repository.path
        try await Self.signable(path)
        try await Self.commit("base", in: path)
        let base = try #require(await world.service.git.tip(of: "main", worktreePath: path))
        try await TestSupport.runGit(["checkout", "-b", "side", "main"], in: path)
        try "side".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["commit", "-am", "Side change"], in: path)
        try await TestSupport.runGit(["checkout", "main"], in: path)
        try "main".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["commit", "-am", "Main change"], in: path)
        await #expect(throws: CommandError.self) {
            try await TestSupport.runGit(["merge", "--no-gpg-sign", "side"], in: path)
        }
        try "resolved".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["commit", "-am", "Resolve merge"], in: path)
        try await TestSupport.runGit(["branch", "-d", "side"], in: path)
        try await TestSupport.runGit(["clone", "-q", path, world.root + "/origin"], in: path)
        try await TestSupport.runGit(["config", "user.name", "Test"], in: world.root + "/origin")
        try await TestSupport.runGit(["config", "user.email", "test@example.com"], in: world.root + "/origin")
        try await TestSupport.runGit(["remote", "add", "origin", world.root + "/origin"], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            try await Self.commit(branch + " work", in: path)
        }
        try await TestSupport.runGit(["branch", "-f", "main", base], in: path)
        world.service.rememberFetch(repositoryPath: path)
        return world
    }
}
