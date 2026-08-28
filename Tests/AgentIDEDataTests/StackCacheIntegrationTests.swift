@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Deriving a stack is thirty git processes, so the answer is kept
/// against where every branch points: these pin when that answer is
/// reused and when it is worked out again.
struct StackCacheIntegrationTests {
    // MARK: Internal

    @Test
    func `a stack is derived again only when a branch has moved`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        try await Self.commit("first", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "-b", "lower"], in: repository.path)
        try await Self.commit("lower work", in: repository.path)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "lower",
            path: repository.path,
        )

        let first = await world.service.stack(for: worktree)
        // Nothing moved: the same answer, without asking git about
        // every branch's fork point a second time.
        #expect(await world.service.stack(for: worktree) == first)

        _ = try await TestSupport.runGit(["checkout", "-b", "upper"], in: repository.path)
        try await Self.commit("upper work", in: repository.path)

        // A branch that has moved is a stack that has changed.
        let second = await world.service.stack(for: worktree)
        #expect(second.branches == ["lower", "upper"])
    }

    @Test
    func `a fetch that moves the default branch is a stack that has changed`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        try await Self.commit("first", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "-b", "lower"], in: repository.path)
        try await Self.commit("lower work", in: repository.path)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "lower",
            path: repository.path,
        )

        #expect(await world.service.stack(for: worktree).branches == ["lower"])

        // Every fork point is measured against the default branch,
        // so a fetch moving it changes what a stack is while every
        // local branch stays exactly where it was: the fingerprint
        // has to see the remote refs, not only the local ones.
        let moved = try await TestSupport.runGit(["rev-parse", "lower"], in: repository.path)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let git = GitClient(runner: FoundationProcessRunner())
        let before = await git.refFingerprint(worktreePath: repository.path)
        _ = try await TestSupport.runGit(
            ["update-ref", "refs/remotes/origin/main", moved],
            in: repository.path,
        )
        let after = await git.refFingerprint(worktreePath: repository.path)

        #expect(before != after)
    }

    // MARK: Private

    /// A commit of its own, so this suite needs nothing from the
    /// derivation's.
    private static func commit(_ message: String, in path: String) async throws {
        let file = path + "/" + message.replacing(" ", with: "_") + ".txt"
        try message.write(toFile: file, atomically: true, encoding: .utf8)
        _ = try await TestSupport.runGit(["add", "."], in: path)
        _ = try await TestSupport.runGit(["commit", "-m", message], in: path)
    }
}
