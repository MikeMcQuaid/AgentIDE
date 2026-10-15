@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Checking out a branch already on origin as a worktree of its own.
struct RemoteBranchWorktreeTests {
    // MARK: Internal

    @Test
    func `origin's branches leave out HEAD, the default branch and branches a worktree holds`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await makeOrigin(in: world, branches: ["feature/new", "held"])
        try await TestSupport.runGit(
            ["worktree", "add", world.root + "/held", "held"],
            in: world.repository.path,
        )

        let branches = await world.service.remoteBranches(repository: world.repository, fetching: false)

        #expect(branches.map(\.name) == ["feature/new"])
    }

    @Test
    func `a branch only on origin becomes a worktree tracking it`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let origin = try await makeOrigin(in: world, branches: ["feature/new"])
        let git = world.service.git
        let tip = await git.commitHash(of: "refs/heads/feature/new", worktreePath: origin)

        let path = try await world.service.openRemoteBranch("feature/new", repository: world.repository)

        #expect(path.hasSuffix("/repo/feature-new"))
        #expect(await git.currentBranch(worktreePath: path) == "feature/new")
        #expect(await git.commitHash(of: "HEAD", worktreePath: path) == tip)
        let upstream = try await TestSupport.runGit(
            ["for-each-ref", "--format=%(upstream)", "refs/heads/feature/new"],
            in: path,
        )
        #expect(upstream.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            == "refs/remotes/origin/feature/new")
    }

    @Test(arguments: [false, true])
    func `a local branch of the same name fast-forwards but never loses a commit`(diverged: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = try await makeOrigin(in: world, branches: ["work"])
        try await TestSupport.runGit(["branch", "work", "main"], in: path)
        if diverged {
            try await TestSupport.runGit(["checkout", "-q", "work"], in: path)
            try await TestSupport.runGit(["commit", "-q", "--allow-empty", "-m", "Local only"], in: path)
            try await TestSupport.runGit(["checkout", "-q", "main"], in: path)
        }
        let git = world.service.git
        let local = await git.commitHash(of: "refs/heads/work", worktreePath: path)
        let remote = await git.commitHash(of: "refs/heads/work", worktreePath: origin)

        let worktree = try await world.service.openRemoteBranch("work", repository: world.repository)

        #expect(await git.commitHash(of: "HEAD", worktreePath: worktree) == (diverged ? local : remote))
        let upstream = try await TestSupport.runGit(
            ["for-each-ref", "--format=%(upstream)", "refs/heads/work"],
            in: worktree,
        )
        #expect(upstream.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/remotes/origin/work")
    }

    @Test
    func `branches whose names flatten to one directory each get their own`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await makeOrigin(in: world, branches: ["a/b", "a-b"])

        let first = try await world.service.openRemoteBranch("a/b", repository: world.repository)
        let second = try await world.service.openRemoteBranch("a-b", repository: world.repository)

        #expect(first.hasSuffix("/repo/a-b"))
        #expect(second.hasSuffix("/repo/a-b-2"))
        #expect(await world.service.git.currentBranch(worktreePath: second) == "a-b")
    }

    @Test
    func `a branch gone from origin is refused before anything is created`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await makeOrigin(in: world, branches: [])

        await #expect(throws: SessionServiceError.self) {
            try await world.service.openRemoteBranch("missing", repository: world.repository)
        }
        #expect(try await world.service.git.worktrees(of: world.repository).isEmpty)
    }

    // MARK: Private

    /// A bare origin holding `main` and each branch one commit ahead
    /// of it, fetched into the world's repository; returns its path.
    @discardableResult
    private func makeOrigin(in world: World, branches: [String]) async throws -> String {
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", "-b", "main", origin], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "main"], in: path)
        for branch in branches {
            try await TestSupport.runGit(["checkout", "-q", "-b", branch], in: path)
            try await TestSupport.runGit(["commit", "-q", "--allow-empty", "-m", "Work on " + branch], in: path)
            try await TestSupport.runGit(["push", "-q", "origin", branch], in: path)
            try await TestSupport.runGit(["checkout", "-q", "main"], in: path)
            try await TestSupport.runGit(["branch", "-q", "-D", branch], in: path)
        }
        try await TestSupport.runGit(["fetch", "-q", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: path)
        world.service.rememberFetch(repositoryPath: path)
        return origin
    }
}
