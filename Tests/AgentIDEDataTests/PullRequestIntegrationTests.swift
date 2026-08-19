@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the pull request flows end to end against real git:
/// the signing gates and the draft file. In its own file to keep the
/// session integration tests under the length limit.
struct PullRequestIntegrationTests {
    @Test
    func `unsigned tips block pushes and rebases target origin's default`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let bare = try TestSupport.temporaryDirectory("signing-origin") + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "main"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)

        // The test repository signs nothing, so the checks refuse
        // and pushing throws instead of shipping unsigned commits.
        let git = GitClient(runner: FoundationProcessRunner())
        #expect(await git.isCommitSigned(worktreePath: path) == false)
        #expect(await git.allCommitsSigned(worktreePath: path, range: "origin/HEAD..HEAD"))

        let worktree = Worktree(
            repositoryName: world.repository.name,
            repositoryPath: path,
            branch: "main",
            path: path,
        )
        await #expect(throws: (any Error).self) {
            try await world.service.push(worktree: worktree)
        }

        // Without an origin ref the branch rebases onto origin/HEAD;
        // pushed but unsigned, its own ref still loses.
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try "more\n".write(toFile: path + "/more.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-m", "Add more"], in: path)
        #expect(await world.service.signedRebaseTarget(worktreePath: path, branch: "feature") == "origin/HEAD")

        try await TestSupport.runGit(["push", "-q", "-u", "origin", "feature"], in: path)
        #expect(await git.remoteBranchExists(worktreePath: path, branch: "feature"))
        #expect(await world.service.signedRebaseTarget(worktreePath: path, branch: "feature") == "origin/HEAD")

        // Amending a pushed commit leaves what was pushed behind as
        // a stale twin rather than a parent, so rebasing there would
        // replay the amended work on top of what it replaced.
        try await TestSupport.runGit(["commit", "-q", "--amend", "-m", "Add more, again"], in: path)
        #expect(await git.isAncestor(worktreePath: path, ref: "origin/feature", of: "HEAD") == false)
        #expect(await world.service.signedRebaseTarget(worktreePath: path, branch: "feature") == "origin/HEAD")
    }
}
