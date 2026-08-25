@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Directories of your own: listed under a repository, shown as
/// rows, and never given to the sandbox.
struct HostDirectoryTests {
    @Test
    func `a listed directory becomes a row of the repository it was listed under`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        let directory = world.root + "/dotfiles"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        world.service.addHostDirectory(directory, to: repository)
        let group = try #require(await world.service.overview().groups.first { $0.repository.path == repository.path })
        let row = try #require(group.items.first { $0.worktree.path == directory })

        #expect(row.worktree.isHostDirectory)
        #expect(row.worktree.repositoryName == repository.name)
        #expect(row.session == nil)
        // Last, after the worktrees it is listed beneath.
        #expect(group.items.last?.worktree.path == directory)

        world.service.forgetHostDirectory(directory, from: repository.path)
        let after = try #require(await world.service.overview().groups.first { $0.repository.path == repository.path })
        #expect(after.items.contains { $0.worktree.path == directory } == false)
        // Forgetting lists it no longer and deletes nothing.
        #expect(FileManager.default.fileExists(atPath: directory))
    }

    @Test
    func `an agent is refused anywhere outside the shared workspace`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let outside = world.root + "/dotfiles"
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)

        await #expect(throws: (any Error).self) {
            try await world.service.launchAgent(
                in: Worktree(
                    repositoryName: "repo",
                    repositoryPath: outside,
                    branch: "main",
                    path: outside,
                    isHostDirectory: true,
                ),
                prompt: "do something",
                agent: .claudeCode,
            )
        }
    }
}
