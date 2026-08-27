@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Stacks are inferred from ancestry in a real repository: the
/// branches sharing a line of descent, ordered by how far each has
/// come from the default branch.
struct BranchStackIntegrationTests {
    // MARK: Internal

    @Test
    func `a stack is every branch on this one's line of descent, in order`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "main",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "middle", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        // Off to one side: same repository, not this line of work.
        _ = try await TestSupport.runGit(["checkout", "-b", "elsewhere", "main"], in: repository.path)
        try await Self.commit("unrelated", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "middle"], in: repository.path)

        let stack = await world.service.stack(for: worktree)

        #expect(stack.branches == ["lower", "middle", "upper"])
        #expect(stack.checkedOut == "middle")
        #expect(stack.parent(of: "middle") == "lower")
        #expect(stack.branches.contains("elsewhere") == false)
    }

    @Test
    func `a stack the default branch has moved past is still a stack`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "upper",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        // The default branch gains work of its own, as it does while
        // a stack is in review: neither branch descends from it any
        // more, which is exactly what a restack is for.
        _ = try await TestSupport.runGit(["checkout", "main"], in: repository.path)
        try await Self.commit("someone else's merge", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "upper"], in: repository.path)

        let stack = await world.service.stack(for: worktree)

        #expect(stack.branches == ["lower", "upper"])
        #expect(stack.parent(of: "upper") == "lower")
    }

    @Test
    func `a pull request opens against the branch below it, or the default branch`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "upper",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        let stack = await world.service.stack(for: worktree)

        // Both ends of `gh pr create` are named: the bottom of a
        // stack opens against the default branch exactly as a branch
        // on its own does, and only an entry above it names another
        // branch. Left unsaid, `gh` took whatever was checked out.
        let bottom = try await world.service.base(for: "lower", in: stack, of: worktree)
        let top = try await world.service.base(for: "upper", in: stack, of: worktree)

        #expect(bottom == "main")
        #expect(top == "lower")
    }

    @Test
    func `two branches at one commit are one entry, the checked-out name standing for both`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "upper",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        // A rename that left the old name behind, and a branch cut
        // by mistake at the same commit: neither is a new entry.
        _ = try await TestSupport.runGit(["branch", "upper-old", "upper"], in: repository.path)
        _ = try await TestSupport.runGit(["branch", "aaa-mistake", "lower"], in: repository.path)
        // The remote knows `lower`, which is what makes it the real
        // name rather than the copy beside it.
        _ = try await TestSupport.runGit(["update-ref", "refs/remotes/origin/lower", "lower"], in: repository.path)

        let stack = await world.service.stack(for: worktree)

        #expect(stack.branches == ["lower", "upper"])
    }

    @Test
    func `a branch's commit messages are its own even where origin/HEAD is unset`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "feature",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        try await Self.commit("second", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "-b", "feature"], in: repository.path)
        try await Self.commit("feature work", in: repository.path)

        // This repository has no remote, so `origin/HEAD` names
        // nothing; git given the raw range listed the branch back
        // to the root, every commit on main included.
        let messages = await world.service.commitMessages(worktree: worktree, range: "origin/HEAD..feature")
        #expect(messages == ["feature work"])

        // A remote default branch ahead of the branch's fork point,
        // and a local main behind it: the span starts where the
        // branch forked, so neither side's extra commits count.
        _ = try await TestSupport.runGit(["checkout", "main"], in: repository.path)
        try await Self.commit("later on main", in: repository.path)
        _ = try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "main"], in: repository.path)
        _ = try await TestSupport.runGit(["reset", "-q", "--hard", "HEAD~2"], in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "feature"], in: repository.path)
        let forked = await world.service.commitMessages(worktree: worktree, range: "origin/HEAD..feature")
        #expect(forked == ["feature work"])
    }

    @Test
    func `a branch left out of the stack stops being counted in it`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "main",
            path: repository.path,
        )
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "middle", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        _ = try await TestSupport.runGit(["checkout", "middle"], in: repository.path)

        world.service.setStackExclusion(branch: "upper", excluded: true, worktreePath: repository.path)

        var stack = await world.service.stack(for: worktree)
        #expect(stack.branches == ["lower", "middle"])
        #expect(world.service.excludedStackBranches(worktreePath: repository.path) == ["upper"])

        // The checked-out branch is the one branch the worktree
        // undeniably holds, so excluding it changes nothing.
        world.service.setStackExclusion(branch: "middle", excluded: true, worktreePath: repository.path)
        stack = await world.service.stack(for: worktree)
        #expect(stack.branches.contains("middle"))

        world.service.setStackExclusion(branch: "upper", excluded: false, worktreePath: repository.path)
        stack = await world.service.stack(for: worktree)
        #expect(stack.branches == ["lower", "middle", "upper"])
    }

    @Test
    func `restacking moves what has fallen behind and leaves the rest alone`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "upper",
            path: repository.path,
        )
        try await Self.signable(repository.path)
        try await Self.commit("first", in: repository.path)
        for branch in ["lower", "upper"] {
            _ = try await TestSupport.runGit(["checkout", "-b", branch], in: repository.path)
            try await Self.commit(branch + " work", in: repository.path)
        }
        // The lower branch gains a commit, leaving the upper behind.
        _ = try await TestSupport.runGit(["checkout", "lower"], in: repository.path)
        try await Self.commit("more lower work", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "upper"], in: repository.path)
        let before = try await Self.tip(of: "upper", in: repository.path)

        let moved = try await world.service.restack(worktree: worktree)

        #expect(moved == ["upper"])
        #expect(try await Self.tip(of: "upper", in: repository.path) != before)
        // Rebased onto the branch below, carrying its own commit.
        let log = try await TestSupport.runGit(["log", "--format=%s", "lower..upper"], in: repository.path)
        #expect(log.standardOutput.contains("upper work"))
        #expect(log.standardOutput.contains("more lower work") == false)
        #expect(try await Self.branch(in: repository.path) == "upper")

        // Nothing left to do, so nothing is renamed for nothing.
        let again = try await world.service.restack(worktree: worktree)
        #expect(again.isEmpty)
    }

    // MARK: Private

    /// Gives the repository a signing key of its own, since a
    /// restack signs everything it replays and the runner has no
    /// key: SSH signing needs nothing but a keypair.
    private static func signable(_ path: String) async throws {
        let key = path + "/.signing-key"
        _ = try await TestSupport.run(["/usr/bin/ssh-keygen", "-t", "ed25519", "-N", "", "-q", "-f", key])
        _ = try await TestSupport.runGit(["config", "gpg.format", "ssh"], in: path)
        _ = try await TestSupport.runGit(["config", "user.signingkey", key], in: path)
    }

    private static func commit(_ message: String, in path: String) async throws {
        let file = path + "/" + message.replacing(" ", with: "_") + ".txt"
        try message.write(toFile: file, atomically: true, encoding: .utf8)
        _ = try await TestSupport.runGit(["add", "."], in: path)
        _ = try await TestSupport.runGit(["commit", "--no-gpg-sign", "-m", message], in: path)
    }

    private static func tip(of branch: String, in path: String) async throws -> String {
        try await TestSupport.runGit(["rev-parse", branch], in: path).standardOutput
    }

    private static func branch(in path: String) async throws -> String {
        try await TestSupport.runGit(["branch", "--show-current"], in: path)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
