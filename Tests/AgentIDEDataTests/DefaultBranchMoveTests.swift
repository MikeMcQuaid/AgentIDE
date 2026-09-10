import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A default branch that moved on the remote is followed by an
/// explicit fetch: origin's HEAD is asked again and a checkout on
/// the old default moves to the new.
struct DefaultBranchMoveTests {
    @Test
    func `the checkout follows a default branch that moved from trunk to main`() async throws {
        let base = try TestSupport.temporaryDirectory("default-move")
        let origin = base + "/origin.git"
        let path = base + "/repo"
        try await TestSupport.runGit(["init", "-q", "--bare", "-b", "trunk", origin], in: base)
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["branch", "-m", "main", "trunk"], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "trunk"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let repository = Repository(name: "repo", path: path)
        #expect(await git.defaultBaseRef(of: repository) == "origin/trunk")

        // GitHub renames the default branch: main appears, HEAD moves.
        try await TestSupport.runGit(["push", "-q", "origin", "trunk:main"], in: path)
        try await TestSupport.runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: origin)

        let move = try await git.followDefaultBranch(of: repository)
        #expect(move == GitClient.DefaultBranchMove(previous: "trunk", current: "main"))
        #expect(await git.defaultBaseRef(of: repository) == "origin/main")
        #expect(await git.currentBranch(worktreePath: path) == "main")
        // Nothing moved is nothing to follow.
        #expect(try await git.followDefaultBranch(of: repository) == nil)
    }
}
