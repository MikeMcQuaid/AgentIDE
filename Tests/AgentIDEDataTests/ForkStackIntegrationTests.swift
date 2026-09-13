@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct ForkStackIntegrationTests {
    @Test(arguments: ["branch", "restack", "push"])
    func `a stack containing a fork refuses changes before touching any branch`(action: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let git = GitClient(runner: FoundationProcessRunner())
        try await BranchStackIntegrationTests.signable(path)
        try ".signing-key*\n.allowed-signers\n".write(
            toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        let origin = world.root + "/origin.git"
        let fork = world.root + "/fork.git"
        try await TestSupport.runGit(["clone", "-q", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["clone", "-q", "--bare", origin, fork], in: path)
        try await TestSupport.runGit(["remote", "add", "contributor", fork], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["checkout", "-q", "-b", branch], in: path)
            try await TestSupport.runGit(["commit", "-q", "--allow-empty", "-S", "-m", branch], in: path)
        }
        try await TestSupport.runGit(["push", "-q", "contributor", "upper"], in: path)
        try await TestSupport.runGit(["checkout", "-q", "lower"], in: path)
        let before = await git.refFingerprint(worktreePath: path)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "lower", path: path)
        #expect(await world.service.stack(for: worktree).stackingBlocker == nil)
        try await TestSupport.runGit(["config", "branch.upper.pushremote", "contributor"], in: path)

        do {
            switch action {
            case "branch":
                try await world.service.stackBranch(named: "child", on: worktree)

            case "restack":
                _ = try await world.service.restack(worktree: worktree)

            default:
                _ = try await world.service.pushStack(worktree: worktree)
            }
            Issue.record("A fork stack must refuse \(action)")
        } catch {
            #expect(error.localizedDescription.contains("fork"))
        }

        #expect(await git.refFingerprint(worktreePath: path) == before)
        #expect(await git.currentBranch(worktreePath: path) == "lower")
        #expect(await git.refExists(worktreePath: origin, ref: "refs/heads/lower") == false)
    }
}
