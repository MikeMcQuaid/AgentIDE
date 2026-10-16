import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct StackPushIntegrationTests {
    @Test
    func `integrating a stack parent keeps its children on top`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        try ".signing-key*\n.allowed-signers\n".write(
            toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            try branch.write(toFile: path + "/" + branch + ".txt", atomically: true, encoding: .utf8)
            try await TestSupport.runGit(["add", branch + ".txt"], in: path)
            try await TestSupport.runGit(["commit", "-S", "-m", branch], in: path)
            try await TestSupport.runGit(["push", "--set-upstream", "origin", branch], in: path)
        }
        let elsewhere = world.root + "/elsewhere"
        try await TestSupport.runGit(["clone", "--branch", "lower", origin, elsewhere], in: path)
        try "remote work".write(toFile: elsewhere + "/remote", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "remote"], in: elsewhere)
        try await TestSupport.runGit(
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Remote work"],
            in: elsewhere,
        )
        try await TestSupport.runGit(["push", "origin", "lower"], in: elsewhere)
        let git = GitClient(runner: FoundationProcessRunner())
        #expect(await git.isCommitSigned(worktreePath: path, ref: "lower"))
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "upper", path: path)
        #expect(try await world.service.pushStack(worktree: worktree) == ["lower", "upper"])
        #expect(await git.isAncestor("lower", of: "upper", worktreePath: path))
        #expect(await git.isAncestor("lower", of: "upper", worktreePath: origin))
        #expect(await git.currentBranch(worktreePath: path) == "upper")
        #expect(try String(contentsOfFile: path + "/remote", encoding: .utf8) == "remote work")
    }
}
