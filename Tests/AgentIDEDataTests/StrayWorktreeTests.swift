@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// A worktree an agent cut from a base clone of its own, which the
/// canonical checkout's listing does not know, still belongs in the
/// sidebar where it can run sessions and be deleted.
struct StrayWorktreeTests {
    @Test
    func `a stray worktree from a foreign base clone is listed`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let container = world.paths.worktreesDirectory + "/repo"
        let base = container + "/.base"
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        try await TestSupport.runGit(["clone", "-q", world.repository.path, base], in: world.root)
        try await TestSupport.runGit(
            ["worktree", "add", "-q", "-b", "stray_work", container + "/stray_work"],
            in: base,
        )

        let overview = await world.service.overview()
        let item = overview.groups.first?.items.first { $0.worktree.branch == "stray_work" }
        #expect(item != nil)
        #expect(item?.worktree.path == container + "/stray_work")
        // Branch work and deletion must land on the owning clone,
        // not the canonical checkout that never heard of the branch.
        #expect(item?.worktree.repositoryPath == base)
    }
}
