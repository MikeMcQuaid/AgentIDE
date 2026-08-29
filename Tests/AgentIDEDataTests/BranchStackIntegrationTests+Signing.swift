@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// The signing half of restacking, split from the main suite for
/// the type length limit.
extension BranchStackIntegrationTests {
    @Test
    func `an in-place branch with an unsigned tip is restacked to sign it`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "only",
            path: repository.path,
        )
        try await Self.signable(repository.path)
        try await Self.signedCommit("first", in: repository.path)
        _ = try await TestSupport.runGit(["checkout", "-b", "only"], in: repository.path)
        try await Self.commit("unsigned work", in: repository.path)
        let before = try await Self.tip(of: "only", in: repository.path)

        // Nothing is out of place, but the tip is unsigned and Push
        // waits on the signature only this rebase can give it;
        // skipping the branch left both buttons dead.
        let moved = try await world.service.restack(worktree: worktree)

        #expect(moved == ["only"])
        #expect(try await Self.tip(of: "only", in: repository.path) != before)

        // Signed now, so the second pass really has nothing to do.
        let again = try await world.service.restack(worktree: worktree)
        #expect(again.isEmpty)
    }

    /// A commit signed with the repository's own key, for setups
    /// whose in-place branches must be left alone by a restack.
    static func signedCommit(_ message: String, in path: String) async throws {
        let file = path + "/" + message.replacing(" ", with: "_") + ".txt"
        try message.write(toFile: file, atomically: true, encoding: .utf8)
        _ = try await TestSupport.runGit(["add", "."], in: path)
        _ = try await TestSupport.runGit(["commit", "-S", "-m", message], in: path)
    }
}
