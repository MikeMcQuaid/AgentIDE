@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the pull request flows end to end against real git:
/// the signing gates and the draft file. In its own file to keep the
/// session integration tests under the length limit.
struct PullRequestIntegrationTests {
    // MARK: Internal

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
        #expect(await git.isAncestor("origin/feature", of: "HEAD", worktreePath: path) == false)
        #expect(await world.service.signedRebaseTarget(worktreePath: path, branch: "feature") == "origin/HEAD")
    }

    @Test(arguments: ["origin", "contributor"], [false, true])
    func `push fetches and integrates remote work`(remote: String, alreadyFetched: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let bare = try await addRemote(remote, to: world)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try "ours\n".write(toFile: path + "/ours.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-m", "Add ours"], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", remote, "feature"], in: path)
        try await BranchStackIntegrationTests.signable(path)
        try ".signing-key*\n.allowed-signers\n".write(
            toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        try "local\n".write(toFile: path + "/local.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "local.txt"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-S", "-m", "Local work"], in: path)

        // Remote work must be integrated even after a background fetch.
        let elsewhere = try TestSupport.temporaryDirectory("moved-clone") + "/clone"
        try await TestSupport.runGit(["clone", "-q", bare, elsewhere], in: world.root)
        try await TestSupport.runGit(["checkout", "-q", "feature"], in: elsewhere)
        try "theirs\n".write(toFile: elsewhere + "/theirs.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: elsewhere)
        try await TestSupport.runGit(
            [
                "-c", "user.name=Elsewhere", "-c", "user.email=elsewhere@example.com",
                "commit", "-q", "--no-gpg-sign", "-m", "Add theirs",
            ],
            in: elsewhere,
        )
        try await TestSupport.runGit(["push", "-q", "origin", "feature"], in: elsewhere)
        if alreadyFetched {
            try await TestSupport.runGit(["fetch", "-q", remote], in: path)
        }

        let git = GitClient(runner: FoundationProcessRunner())
        try await git.push(worktreePath: path, branch: "feature", remote: remote)
        #expect(await git.tip(of: "feature", worktreePath: bare) == git.tip(of: "feature", worktreePath: path))
        #expect(try String(contentsOfFile: path + "/theirs.txt", encoding: .utf8) == "theirs\n")
        #expect(try String(contentsOfFile: path + "/local.txt", encoding: .utf8) == "local\n")
        #expect(await git.isCommitSigned(worktreePath: path))
    }

    @Test(arguments: ["origin", "contributor"])
    func `a rewritten remote that conflicts is set aside and replaced by push`(remote: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        try ".signing-key*\n.allowed-signers\n".write(
            toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        let bare = try await addRemote(remote, to: world)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try "ours\n".write(toFile: path + "/claim.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "claim.txt"], in: path)
        try await TestSupport.runGit(["commit", "-q", "--no-gpg-sign", "-m", "Claim"], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", remote, "feature"], in: path)

        // Rewritten elsewhere with conflicting content, and locally
        // amended too: the histories share no tip, and the remote's
        // was never seen here.
        let elsewhere = try TestSupport.temporaryDirectory("rewritten-clone") + "/clone"
        try await TestSupport.runGit(["clone", "-q", bare, elsewhere], in: world.root)
        try await TestSupport.runGit(["checkout", "-q", "feature"], in: elsewhere)
        try "theirs\n".write(toFile: elsewhere + "/claim.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(
            [
                "-c", "user.name=Elsewhere", "-c", "user.email=elsewhere@example.com",
                "commit", "-q", "-a", "--amend", "--no-gpg-sign", "-m", "Claim, rewritten",
            ],
            in: elsewhere,
        )
        try await TestSupport.runGit(["push", "-q", "--force", "origin", "feature"], in: elsewhere)
        try "ours, amended\n".write(toFile: path + "/claim.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(
            ["commit", "-q", "-a", "--amend", "--no-gpg-sign", "-m", "Claim, amended"],
            in: path,
        )
        try await TestSupport.runGit(["fetch", "-q", remote], in: path)

        let git = GitClient(runner: FoundationProcessRunner())
        let original = await git.tip(of: "feature", worktreePath: path)
        let remoteTip = await git.tip(of: "feature", worktreePath: bare)
        await #expect(throws: CommandError.self) {
            try await git.push(worktreePath: path, branch: "feature", remote: remote)
        }
        #expect(await git.tip(of: "feature", worktreePath: path) == original)
        #expect(await git.tip(of: "feature", worktreePath: bare) == remoteTip)
        #expect(await git.currentBranch(worktreePath: path) == "feature")
        #expect(await git.isDirty(worktreePath: path) == false)

        // An explicit Rebase can still set aside the conflicting remote version.
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "feature", path: path)
        try await world.service.rebaseSigned(worktree: worktree)
        _ = try await world.service.push(worktree: worktree)
        let local = try await TestSupport.runGit(["rev-parse", "feature"], in: path).standardOutput
        let pushed = try await TestSupport.runGit(["rev-parse", "feature"], in: bare).standardOutput
        #expect(local == pushed)
    }

    @Test(arguments: [false, true])
    func `a newer default branch is rebased even when pushed commits are signed`(hasLocalCommit: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        try ".signing-key*\n.allowed-signers\n".write(
            toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        _ = try await addRemote("origin", to: world)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try "feature\n".write(toFile: path + "/feature.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "feature.txt"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-S", "-m", "Feature"], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "feature"], in: path)
        if hasLocalCommit {
            try await TestSupport.runGit(["commit", "-q", "-S", "--allow-empty", "-m", "Local work"], in: path)
        }
        try await TestSupport.runGit(["checkout", "-q", "main"], in: path)
        for message in ["First update", "Second update"] {
            try await TestSupport.runGit(["commit", "-q", "-S", "--allow-empty", "-m", message], in: path)
        }
        try await TestSupport.runGit(["push", "-q", "origin", "main"], in: path)
        try await TestSupport.runGit(["checkout", "-q", "feature"], in: path)

        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "feature", path: path)
        #expect(await world.service.signedRebaseTarget(worktreePath: path, branch: "feature") == "origin/HEAD")
        #expect(await world.service.rebaseNeed(worktree: worktree) == .rebase)
        #expect(try await world.service.rebaseSigned(worktree: worktree) == "origin/HEAD")
        #expect(await world.service.git.isAncestor("origin/main", of: "feature", worktreePath: path))
    }

    // MARK: Private

    private func addRemote(_ remote: String, to world: World) async throws -> String {
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", origin], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "main"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        guard remote != "origin" else {
            return origin
        }

        let fork = world.root + "/contributor.git"
        try await TestSupport.runGit(["clone", "-q", "--bare", origin, fork], in: path)
        try await TestSupport.runGit(["remote", "add", remote, fork], in: path)
        return fork
    }
}
