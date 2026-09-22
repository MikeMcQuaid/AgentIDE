import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct LocalReviewRevisionTests {
    @Test(arguments: AgentKind.allCases)
    func `other reviewer falls back to the general session default`(agent: AgentKind) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(agent.rawValue, forKey: "agentKind")
        let path = world.repository.path
        #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) != agent)
        let store = MetadataStore(file: world.paths.metadataFile)
        store.update { $0.sessionsByWorktree[path] = "unknown-agent" }
        #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) != agent)
        let other: AgentKind = agent == .codexCLI ? .claudeCode : .codexCLI
        store.update { $0.sessionsByWorktree[path] = SessionName.make(repository: "r", branch: "b", agent: other) }
        #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) == agent)
        defaults.set(other.rawValue, forKey: AppSettings.reviewAgentKey)
        #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) == other)
    }

    @Test
    func `untracked changes and new commits invalidate a worktree revision`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let original = try await world.service.localReviewRevision(worktreePath: path)
        try "new content\n".write(toFile: path + "/untracked.swift", atomically: true, encoding: .utf8)
        let dirty = try await world.service.localReviewRevision(worktreePath: path)
        #expect(dirty != original)
        try await TestSupport.runGit(["add", "--", "untracked.swift"], in: path)
        try await TestSupport.runGit(["commit", "-m", "Add source"], in: path)
        let committed = try await world.service.localReviewRevision(worktreePath: path)
        #expect(committed != dirty)
        #expect(committed != original)
    }

    @Test
    func `host directories cannot start a reviewer`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        await #expect(throws: (any Error).self) {
            try await world.service.runLocalReview(
                files: [],
                worktreePath: world.root,
                reviewer: .codexCLI,
            )
        }
    }

    @Test
    func `reviewer defaults to the other agent and persisted feedback survives service reads`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let store = MetadataStore(file: world.paths.metadataFile)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for agent in AgentKind.allCases {
            store.update { metadata in
                metadata.sessionsByWorktree[path] = SessionName.make(repository: "repo", branch: "topic", agent: agent)
            }
            #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) != agent)
            defaults.set(agent.rawValue, forKey: AppSettings.reviewAgentKey)
            #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) == agent)
            defaults.set("", forKey: AppSettings.reviewAgentKey)
        }
        defaults.set("removed-agent", forKey: AppSettings.reviewAgentKey)
        #expect(world.service.localReviewer(worktreePath: path, defaults: defaults) == .claudeCode)
        var review = LocalReview(reviewer: .codexCLI, snapshot: "snapshot", revision: "revision", threads: [])
        review.commentary = "Keep the public API."
        world.service.saveLocalReview(review, worktreePath: path)
        #expect(world.service.localReview(worktreePath: path) == review)
    }
}
