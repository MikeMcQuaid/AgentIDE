import Foundation
import SanductorData
import SanductorDomain
import Testing

/// A default branch that moved on the remote is followed by an
/// explicit fetch: origin's HEAD is asked again and a checkout on
/// the old default moves to the new.
struct DefaultBranchMoveTests {
    @Test
    func `linked worktrees share default branch cache invalidation`() async throws {
        let base = try TestSupport.temporaryDirectory("shared-default")
        defer { try? FileManager.default.removeItem(atPath: base) }
        let path = base + "/repo"
        let linked = base + "/linked"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", linked], in: path)
        try await TestSupport.runGit(["update-ref", "refs/remotes/origin/trunk", "HEAD"], in: path)
        try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "HEAD"], in: path)
        try await TestSupport.runGit(
            ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"], in: path,
        )
        let git = GitClient(runner: FoundationProcessRunner()) { true }
        let repository = Repository(name: "repo", path: path)
        let worktree = Repository(name: "repo", path: linked)
        #expect(await git.defaultBaseRef(of: repository) == "origin/trunk")
        #expect(await git.defaultBaseRef(of: worktree) == "origin/trunk")

        try await TestSupport.runGit(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], in: path)
        try await git.fetch(repositoryPath: linked)

        #expect(await git.defaultBaseRef(of: repository) == "origin/main")
        #expect(await git.defaultBaseRef(of: worktree) == "origin/main")
    }

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
        let git = GitClient(runner: FoundationProcessRunner()) { true }
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
