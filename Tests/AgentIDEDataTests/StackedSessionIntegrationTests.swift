@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A session started on another session's branch: a stack spanning
/// two worktrees.
struct StackedSessionIntegrationTests {
    /// A parent worktree with a commit, and a child cut from it.
    struct Pair {
        let world: World
        let parent: Worktree
        let child: Worktree
    }

    static func pair() async throws -> Pair {
        let world = try await World.make()
        let repository = world.repository
        try await BranchStackIntegrationTests.signable(repository.path)
        let parentPath = try await world.service.createWorktreePath(repository: repository, branch: "part_one")
        try await BranchStackIntegrationTests.commit("part one", in: parentPath)
        let childPath = try await world.service.createWorktreePath(
            repository: repository,
            branch: "part_two",
            base: "part_one",
        )
        try await BranchStackIntegrationTests.commit("part two", in: childPath)
        return Pair(
            world: world,
            parent: Self.worktree("part_one", at: parentPath, in: repository),
            child: Self.worktree("part_two", at: childPath, in: repository),
        )
    }

    static func worktree(_ branch: String, at path: String, in repository: Repository) -> Worktree {
        Worktree(repositoryName: repository.name, repositoryPath: repository.path, branch: branch, path: path)
    }

    @Test
    func `a session on another session's branch starts from its unpushed work and stacks on it`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let service = pair.world.service

        let parentTip = try await BranchStackIntegrationTests.tip(of: "part_one", in: pair.parent.path)
        #expect(await service.git.isAncestor("part_one", of: "part_two", worktreePath: pair.child.path))
        #expect(try await BranchStackIntegrationTests.tip(of: "part_two~1", in: pair.child.path) == parentTip)
        let upstream = try await TestSupport.runGit(
            ["for-each-ref", "--format=%(upstream)", "refs/heads/part_two"],
            in: pair.child.path,
        )
        #expect(upstream.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let stack = await service.stack(for: pair.child)
        #expect(stack.branches == ["part_one", "part_two"])
        #expect(try await service.base(for: "part_two", in: stack, of: pair.child) == "part_one")
        #expect(await service.baseBranches(repository: pair.world.repository).sorted() == ["part_one", "part_two"])
    }

    @Test(arguments: [(false, false), (true, false), (true, true)])
    func `two sessions on one branch each stack on it, never on each other`(
        parentMovedOn: Bool,
        reflogExpired: Bool,
    ) async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let service = pair.world.service
        let repository = pair.world.repository
        let siblingPath = try await service.createWorktreePath(
            repository: repository,
            branch: "part_three",
            base: "part_one",
        )
        try await BranchStackIntegrationTests.commit("part three", in: siblingPath)
        try await BranchStackIntegrationTests.commit("more of part two", in: pair.child.path)
        let sibling = Self.worktree("part_three", at: siblingPath, in: repository)
        if parentMovedOn {
            try await BranchStackIntegrationTests.commit("more of part one", in: pair.parent.path)
        }
        if reflogExpired {
            _ = try await TestSupport.runGit(["reflog", "expire", "--expire=now", "--all"], in: repository.path)
        }

        // Once the parent has moved on, only the reflog says which of
        // the three it was; without it none stacks rather than guess.
        let guessless = parentMovedOn && reflogExpired
        #expect(await service.stack(for: pair.child).branches == (guessless ? ["part_two"] : ["part_one", "part_two"]))
        #expect(await service.stack(for: sibling).branches == (guessless ? ["part_three"] : ["part_one", "part_three"]))
        #expect(await service.stack(for: pair.parent).branches == ["part_one"])
    }

    @Test
    func `a parent that moved on keeps its child off its own stack`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        try await BranchStackIntegrationTests.commit("more of part one", in: pair.parent.path)

        #expect(await pair.world.service.stack(for: pair.parent).branches == ["part_one"])
    }

    @Test
    func `a sibling cut after the parent moved on stacks on the parent, never under the first child`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let service = pair.world.service
        let repository = pair.world.repository
        try await BranchStackIntegrationTests.commit("more of part one", in: pair.parent.path)
        let siblingPath = try await service.createWorktreePath(
            repository: repository,
            branch: "part_three",
            base: "part_one",
        )
        try await BranchStackIntegrationTests.commit("part three", in: siblingPath)
        let sibling = Self.worktree("part_three", at: siblingPath, in: repository)

        #expect(await service.stack(for: pair.child).branches == ["part_one", "part_two"])
        #expect(await service.stack(for: sibling).branches == ["part_one", "part_three"])
        #expect(await service.stack(for: pair.parent).branches == ["part_one", "part_three"])

        _ = try await service.restack(worktree: pair.child)

        #expect(await service.git.isAncestor("part_three", of: "part_two", worktreePath: repository.path) == false)
        #expect(await service.git.isAncestor("part_one", of: "part_two", worktreePath: repository.path))
    }

    @Test
    func `a parent that moved on is still the parent of the one branch cut from it`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        try await BranchStackIntegrationTests.commit("more of part one", in: pair.parent.path)

        #expect(await pair.world.service.stack(for: pair.child).branches == ["part_one", "part_two"])
    }

    @Test
    func `a restack refuses a worktree that has switched away from the branch it held`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let holders = ["part_one": pair.parent.path]
        let service = pair.world.service
        try await service.requireStillHeld("part_one", holders: holders, worktreePath: pair.child.path)

        _ = try await TestSupport.runGit(["checkout", "-b", "elsewhere"], in: pair.parent.path)

        await #expect(throws: CommandError.self) {
            try await service.requireStillHeld("part_one", holders: holders, worktreePath: pair.child.path)
        }
    }

    @Test
    func `a stacked branch's review is against the branch below, named in full`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let service = pair.world.service

        #expect(await service.stackReviewBase(for: pair.child) == "refs/heads/part_one")
        let defaultBase = await service.git.defaultBaseRef(of: pair.world.repository)
        #expect(await service.stackReviewBase(for: pair.parent) == defaultBase)
    }

    @Test
    func `a base branch that no longer exists creates nothing`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        await #expect(throws: SessionServiceError.self) {
            try await world.service.createWorktreePath(repository: world.repository, branch: "orphan", base: "gone")
        }

        #expect(try await world.service.git.worktrees(of: world.repository).isEmpty)
        #expect(await world.service.git.branchExists(repository: world.repository, branch: "orphan") == false)
    }

    @Test
    func `a worktree releasing its branch leaves the cached stack alone`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let git = pair.world.service.git
        let before = await git.refFingerprint(worktreePath: pair.child.path)

        _ = try await TestSupport.runGit(
            ["worktree", "remove", "--force", pair.parent.path],
            in: pair.world.repository.path,
        )

        #expect(await git.refFingerprint(worktreePath: pair.child.path) == before)
        #expect(await git.branchHolders(worktreePath: pair.child.path)["part_one"] == nil)
    }

    @Test
    func `a restack moves a branch another worktree holds inside that worktree`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let repository = pair.world.repository
        try await BranchStackIntegrationTests.commit("main moved on", in: repository.path)

        let moved = try await pair.world.service.restack(worktree: pair.child)

        #expect(moved == ["part_one", "part_two"])
        let git = pair.world.service.git
        #expect(await git.isAncestor("main", of: "part_one", worktreePath: repository.path))
        #expect(await git.isAncestor("part_one", of: "part_two", worktreePath: repository.path))
        #expect(try await BranchStackIntegrationTests.branch(in: pair.parent.path) == "part_one")
        #expect(try await BranchStackIntegrationTests.branch(in: pair.child.path) == "part_two")
        #expect(await git.isDirty(worktreePath: pair.parent.path) == false)
    }

    @Test(arguments: [true, false])
    func `a restack leaves alone a parent worktree that is dirty or busy`(dirty: Bool) async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let repository = pair.world.repository
        try await BranchStackIntegrationTests.commit("main moved on", in: repository.path)
        let before = try await BranchStackIntegrationTests.tip(of: "part_one", in: repository.path)
        if dirty {
            try "unsaved".write(toFile: pair.parent.path + "/scratch.txt", atomically: true, encoding: .utf8)
        }

        await #expect(throws: CommandError.self) {
            try await pair.world.service.restack(
                worktree: pair.child,
                busyWorktrees: dirty ? [] : [pair.parent.path],
            )
        }

        #expect(try await BranchStackIntegrationTests.tip(of: "part_one", in: repository.path) == before)
    }

    @Test
    func `a restack that fails above puts the parent back in its own worktree`() async throws {
        let pair = try await Self.pair()
        defer { pair.world.tearDown() }
        let repository = pair.world.repository
        // The parent moves cleanly, then the child conflicts.
        try "child's".write(toFile: pair.child.path + "/shared.txt", atomically: true, encoding: .utf8)
        _ = try await TestSupport.runGit(["add", "."], in: pair.child.path)
        _ = try await TestSupport.runGit(["commit", "--no-gpg-sign", "-m", "child's shared"], in: pair.child.path)
        try "main's".write(toFile: repository.path + "/shared.txt", atomically: true, encoding: .utf8)
        _ = try await TestSupport.runGit(["add", "."], in: repository.path)
        _ = try await TestSupport.runGit(["commit", "--no-gpg-sign", "-m", "main's shared"], in: repository.path)
        let parentBefore = try await BranchStackIntegrationTests.tip(of: "part_one", in: repository.path)
        let childBefore = try await BranchStackIntegrationTests.tip(of: "part_two", in: repository.path)

        await #expect(throws: (any Error).self) {
            try await pair.world.service.restack(worktree: pair.child)
        }

        #expect(try await BranchStackIntegrationTests.tip(of: "part_one", in: repository.path) == parentBefore)
        #expect(try await BranchStackIntegrationTests.tip(of: "part_two", in: repository.path) == childBefore)
        #expect(try await BranchStackIntegrationTests.branch(in: pair.parent.path) == "part_one")
        #expect(try await BranchStackIntegrationTests.branch(in: pair.child.path) == "part_two")
        #expect(await pair.world.service.git.isDirty(worktreePath: pair.parent.path) == false)
    }
}
