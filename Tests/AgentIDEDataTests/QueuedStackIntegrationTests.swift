@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct QueuedStackIntegrationTests {
    // MARK: Internal

    @Test(arguments: ["lower", "middle", "upper"])
    func `queued stack members stay fixed while branches above are signed and pushed`(queued: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let git = world.service.git
        try await BranchStackIntegrationTests.signable(path)
        try await BranchStackIntegrationTests.commit("base", in: path)
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        let branches = ["lower", "middle", "upper"]
        var before = [String: String]()
        for branch in branches {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            try await BranchStackIntegrationTests.commit(branch, in: path)
            try await TestSupport.runGit(["push", "--set-upstream", "origin", branch], in: path)
            before[branch] = await git.tip(of: branch, worktreePath: path)
        }
        try await TestSupport.runGit(["checkout", "main"], in: path)
        try await BranchStackIntegrationTests.commit("main moved", in: path)
        try await TestSupport.runGit(["push", "origin", "main"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["checkout", "upper"], in: path)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "upper", path: path)
        #expect(await world.service.stackFacts(for: worktree).outOfPlace == ["lower"])
        Self.queue(queued, in: world)
        let movable = Array(branches.drop { $0 != queued }.dropFirst())

        let frozen = Worktree(repositoryName: "repo", repositoryPath: path, branch: "lower", path: path)
        await #expect(throws: SessionServiceError.self) {
            _ = try await world.service.rebaseSigned(worktree: frozen)
        }

        let facts = await world.service.stackFacts(for: worktree)
        #expect(facts.outOfPlace.isEmpty)
        #expect(facts.unsigned == movable)
        #expect(try await world.service.restack(worktree: worktree) == movable)
        #expect(try await world.service.pushStack(worktree: worktree) == movable)
        for branch in branches {
            #expect(await git.isAncestor("origin/main", of: branch, worktreePath: path) == false)
            if movable.contains(branch) == false {
                #expect(await git.tip(of: branch, worktreePath: path) == before[branch])
                #expect(await git.tip(of: branch, worktreePath: origin) == before[branch])
            }
        }
        #expect(await git.currentBranch(worktreePath: path) == "upper")
        world.service.store.update { $0.queuedCache[path] = [] }
        #expect(await world.service.stackFacts(for: worktree).outOfPlace == ["lower"])
    }

    @Test(arguments: ["rebase", "push"])
    func `a queued standalone branch refuses mutation`(action: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        try await BranchStackIntegrationTests.commit("base", in: path)
        try await TestSupport.runGit(["checkout", "-b", "queued"], in: path)
        try await BranchStackIntegrationTests.commit("work", in: path)
        let before = await world.service.git.tip(of: "queued", worktreePath: path)
        Self.queue("queued", in: world)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "queued", path: path)

        #expect(await world.service.rebaseNeed(worktree: worktree) == .nothing)
        await #expect(throws: SessionServiceError.self) {
            if action == "rebase" {
                _ = try await world.service.rebaseSigned(worktree: worktree)
            } else {
                _ = try await world.service.push(worktree: worktree)
            }
        }
        #expect(await world.service.git.tip(of: "queued", worktreePath: path) == before)
    }

    @Test
    func `the queued remote tip anchors children after a previously rejected rebase`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let git = world.service.git
        try await BranchStackIntegrationTests.signable(path)
        try await BranchStackIntegrationTests.commit("base", in: path)
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        for branch in ["queued", "child"] {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            try await BranchStackIntegrationTests.commit(branch, in: path)
            try await TestSupport.runGit(["push", "--set-upstream", "origin", branch], in: path)
        }
        try await TestSupport.runGit(["checkout", "main"], in: path)
        try await BranchStackIntegrationTests.commit("new main", in: path)
        try await TestSupport.runGit(["push", "origin", "main"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["rebase", "origin/main", "queued"], in: path)
        try await TestSupport.runGit(["rebase", "--onto", "queued", "origin/queued", "child"], in: path)
        let queuedTip = await git.tip(of: "queued", worktreePath: path)
        Self.queue("queued", in: world)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "child", path: path)

        #expect(try await world.service.restack(worktree: worktree) == ["child"])
        #expect(try await world.service.pushStack(worktree: worktree) == ["child"])
        #expect(await git.tip(of: "queued", worktreePath: path) == queuedTip)
        #expect(await git.isAncestor("origin/queued", of: "child", worktreePath: path))
        #expect(await git.isAncestor("origin/main", of: "child", worktreePath: path) == false)
        #expect(await git.commitCount(from: "origin/queued", to: "child", worktreePath: path) == 1)
    }

    // MARK: Private

    private static func queue(_ branch: String, in world: World) {
        let path = world.repository.path
        world.service.pullRequestReads.rememberBranchSummary(
            PullRequestSummary(
                number: 1,
                title: "Queued",
                url: "",
                headBranch: branch,
                mergeable: "",
                reviewDecision: "",
                checks: "",
                state: "OPEN",
            ),
            repositoryPath: path,
            branch: branch,
        )
        world.service.store.update { metadata in
            metadata.queuedCache[path] = [1]
            metadata.fetchedAt["queue#" + path] = Date()
        }
    }
}
