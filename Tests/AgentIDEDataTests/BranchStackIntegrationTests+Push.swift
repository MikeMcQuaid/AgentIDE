@testable import AgentIDEData
import Testing

extension BranchStackIntegrationTests {
    @Test(arguments: [false, true])
    func `pushing a stack publishes only through the requested branch`(unsignedTop: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await Self.signable(path)
        try await Self.signedCommit("base", in: path)
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "-q", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], in: path)
        for branch in ["lower", "middle", "upper"] {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            if unsignedTop, branch == "upper" {
                try await Self.commit(branch + " work", in: path)
            } else {
                try await Self.signedCommit(branch + " work", in: path)
            }
        }
        let worktree = StackedSessionIntegrationTests.worktree("lower", at: path, in: world.repository)
        #expect(try await world.service.pushStack(worktree: worktree) == ["lower"])
        #expect(await world.service.git.refExists(worktreePath: origin, ref: "refs/heads/middle") == false)
        #expect(await world.service.git.refExists(worktreePath: origin, ref: "refs/heads/upper") == false)

        try await TestSupport.runGit(["checkout", "lower"], in: path)
        try await Self.signedCommit("lower update", in: path)
        try await TestSupport.runGit(["checkout", "upper"], in: path)
        #expect(try await world.service.restack(worktree: worktree) == ["middle", "upper"])
        #expect(try await world.service.pushStack(worktree: worktree) == ["lower"])
        #expect(try await Self.tip(of: "lower", in: origin) == Self.tip(of: "lower", in: path))
        #expect(await world.service.git.refExists(worktreePath: origin, ref: "refs/heads/middle") == false)
        #expect(await world.service.git.refExists(worktreePath: origin, ref: "refs/heads/upper") == false)

        let middle = StackedSessionIntegrationTests.worktree("middle", at: path, in: world.repository)
        #expect(try await world.service.pushStack(worktree: middle) == ["lower", "middle"])
        #expect(try await Self.tip(of: "middle", in: origin) == Self.tip(of: "middle", in: path))
        #expect(await world.service.git.refExists(worktreePath: origin, ref: "refs/heads/upper") == false)
        #expect(try await Self.branch(in: path) == "upper")

        let upper = StackedSessionIntegrationTests.worktree("upper", at: path, in: world.repository)
        #expect(try await world.service.pushStack(worktree: upper) == ["lower", "middle", "upper"])
        #expect(try await Self.tip(of: "upper", in: origin) == Self.tip(of: "upper", in: path))
    }
}
