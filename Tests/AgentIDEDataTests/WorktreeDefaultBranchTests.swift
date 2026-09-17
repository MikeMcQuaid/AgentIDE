@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A new worktree from an old clone whose default branch GitHub has
/// renamed: `origin/HEAD` still names the old branch, the pruning
/// fetch removes its tracking ref, and the base is followed to where
/// origin's HEAD points now rather than refused.
struct WorktreeDefaultBranchTests {
    @Test
    func `a new worktree follows a default branch the fetch pruned away`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", "-b", "trunk", origin], in: world.root)
        try await TestSupport.runGit(["branch", "-m", "main", "trunk"], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "trunk"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: path)

        // GitHub renames the default branch: main appears, HEAD moves
        // and the old branch is gone.
        try await TestSupport.runGit(["push", "-q", "origin", "trunk:main"], in: path)
        try await TestSupport.runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: origin)
        try await TestSupport.runGit(["push", "-q", "origin", "--delete", "trunk"], in: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let tip = await git.commitHash(of: "main", worktreePath: origin)

        let worktree = try await world.service.createWorktreePath(repository: world.repository, branch: "new-work")

        #expect(await git.commitHash(of: "HEAD", worktreePath: worktree) == tip)
        #expect(await git.defaultBaseRef(of: world.repository) == "origin/main")
        // The main checkout sat on the old default and moved with it.
        #expect(await git.currentBranch(worktreePath: path) == "main")
    }
}
