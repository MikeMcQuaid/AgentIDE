@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A pull request checked out from a fork, which `gh pr checkout`
/// leaves with the fork's URL in the branch's config and no remote
/// named for it.
struct ForkRemoteIntegrationTests {
    // MARK: Internal

    @Test
    func `naming the fork's remote gives the branch something to count against`() async throws {
        let root = try TestSupport.temporaryDirectory("fork")
        defer { try? FileManager.default.removeItem(atPath: root) }

        // The fork sits at a path shaped like the URL it would have,
        // which is what names the remote after its owner.
        let forkPath = root + "/github.com/aholland/brew"
        try await TestSupport.makeRepository(at: forkPath)
        try await TestSupport.runGit(["checkout", "-q", "-b", branch], in: forkPath)
        try "cask\n".write(toFile: forkPath + "/quarantine.rb", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "."], in: forkPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Centralise the checks"], in: forkPath)

        let basePath = root + "/brew"
        try await TestSupport.makeRepository(at: basePath)
        try await checkOutAsGitHubCLIWould(fork: forkPath, into: basePath)

        // What the branch says before anything is named: the URL,
        // and no remote-tracking ref to count against.
        #expect(await git.branchRemote(worktreePath: basePath, branch: branch) == forkPath)
        #expect(await git.refExists(worktreePath: basePath, ref: "aholland/" + branch) == false)

        try await git.adoptRemote(named: "aholland", url: forkPath, branch: branch, worktreePath: basePath)
        #expect(await git.remoteURL(named: "aholland", worktreePath: basePath) == forkPath)
        #expect(await git.refExists(worktreePath: basePath, ref: "aholland/" + branch))
        #expect(await git.branchRemote(worktreePath: basePath, branch: branch) == "aholland")

        // Naming it twice is what a second refresh does.
        try await git.adoptRemote(named: "aholland", url: forkPath, branch: branch, worktreePath: basePath)
        #expect(await git.remoteURL(named: "aholland", worktreePath: basePath) == forkPath)
    }

    @Test
    func `a branch of your own says nothing about a fork`() async throws {
        let root = try TestSupport.temporaryDirectory("origin")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)

        #expect(await git.branchRemote(worktreePath: repoPath, branch: "main") == nil)
        #expect(await git.remoteURL(named: "origin", worktreePath: repoPath) == nil)
    }

    @Test(arguments: [false, true])
    func `signing and leased pushes preserve the fork destination`(collision: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        let origin = world.root + "/origin.git"
        let fork = world.root + "/github.com/contributor/repo.git"
        let remote = collision ? "contributor-2" : "contributor"
        try await TestSupport.runGit(["init", "-q", "--bare", origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["push", "-q", "origin", "main"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["clone", "-q", "--bare", origin, fork], in: path)
        try await TestSupport.runGit(["remote", "add", "contributor", fork], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", branch], in: path)
        try await TestSupport.runGit(["commit", "-q", "--allow-empty", "-S", "-m", "Published"], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "contributor", branch], in: path)
        if collision {
            try await TestSupport.runGit(["remote", "rename", "contributor", "original-fork"], in: path)
            try await TestSupport.runGit(["remote", "add", "contributor", origin], in: path)
            try await TestSupport.runGit(["config", "branch." + branch + ".pushremote", fork], in: path)
        }
        let published = await git.tip(of: branch, worktreePath: path)
        try await TestSupport.runGit(["commit", "-q", "--allow-empty", "-m", "Unsigned"], in: path)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: branch, path: path)

        #expect(try await world.service.rebaseSigned(worktree: worktree) == remote + "/" + branch)
        #expect(await git.tip(of: "HEAD^", worktreePath: path) == published)
        #expect(await world.service.isTipSigned(worktree: worktree))
        #expect(try await world.service.push(worktree: worktree)
            == .contributorFork(owner: "contributor", remote: remote))
        #expect(await git.tip(of: branch, worktreePath: fork) == git.tip(of: branch, worktreePath: path))
        #expect(await git.remoteBranchExists(worktreePath: path, branch: branch) == false)

        #expect(await git.remoteURL(named: remote, worktreePath: path) == fork)
        if collision {
            #expect(await git.remoteURL(named: "contributor", worktreePath: path) == origin)
        }

        try await TestSupport.runGit(["commit", "-q", "--amend", "--allow-empty", "-S", "-m", "Amended"], in: path)
        _ = try await world.service.push(worktree: worktree)
        #expect(await git.tip(of: branch, worktreePath: fork) == git.tip(of: branch, worktreePath: path))

        // A server refusal is surfaced without trying origin.
        try await TestSupport.runGit(["config", "receive.denyNonFastForwards", "true"], in: fork)
        try await TestSupport.runGit(["commit", "-q", "--amend", "--allow-empty", "-S", "-m", "Rewritten"], in: path)
        await #expect(throws: CommandError.self) {
            try await world.service.push(worktree: worktree)
        }
        #expect(await git.tip(of: branch, worktreePath: fork) != git.tip(of: branch, worktreePath: path))
        #expect(await git.remoteBranchExists(worktreePath: path, branch: branch) == false)
    }

    // MARK: Private

    private let branch = "quarantine-capability"

    private let git: GitClient = .init(runner: FoundationProcessRunner())

    /// The state `gh pr checkout` leaves behind for a pull request
    /// from a fork: the branch, the fork's URL in its config and no
    /// remote of its own.
    private func checkOutAsGitHubCLIWould(fork: String, into path: String) async throws {
        try await TestSupport.runGit(["fetch", "-q", fork, branch], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", branch, "FETCH_HEAD"], in: path)
        try await TestSupport.runGit(["config", "branch." + branch + ".remote", fork], in: path)
        try await TestSupport.runGit(["config", "branch." + branch + ".pushremote", fork], in: path)
        try await TestSupport.runGit(
            ["config", "branch." + branch + ".merge", "refs/heads/" + branch],
            in: path,
        )
    }
}
