@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct ForkRemoteCleanupIntegrationTests {
    // MARK: Internal

    @Test(arguments: ["delete", "merge", "missing", "rewrite"])
    func `deleting a PR worktree removes its unused remote`(method: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let topic = try await checkout(in: world)
        if method == "rewrite" {
            try await TestSupport.runGit(
                ["config", "url." + world.root + "/relocated.insteadOf", world.root + "/github.com/contributor/repo"],
                in: world.repository.path,
            )
        }

        if method == "merge" {
            #expect(try await world.service.cleanUpMergedWorktree(item: topic, baseRef: "main") == nil)
        } else {
            if method == "missing" {
                try FileManager.default.removeItem(atPath: topic.worktree.path)
            }
            try await world.service.deleteWorktree(item: topic)
        }

        #expect(FileManager.default.fileExists(atPath: topic.worktree.path) == false)
        #expect(await git.branchExists(repository: world.repository, branch: "topic") == false)
        #expect(await git.remoteURL(named: "contributor", worktreePath: world.repository.path) == nil)
        #expect(await git.remoteURL(named: "origin", worktreePath: world.repository.path) != nil)
    }

    @Test(arguments: ["remote", "pushremote", "url"])
    func `a shared remote survives until its last worktree is deleted`(key: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let topic = try await checkout(in: world)
        let other = item("other", in: world)
        try await TestSupport.runGit(
            ["worktree", "add", "-b", "other", other.worktree.path, "main"],
            in: world.repository.path,
        )
        try await TestSupport.runGit(
            [
                "config", "branch.other." + (key == "url" ? "remote" : key),
                key == "url" ? world.root + "/github.com/contributor/repo" : "contributor",
            ],
            in: world.repository.path,
        )
        try await TestSupport.runGit(["config", "branch.other.merge", "refs/heads/main"], in: world.repository.path)

        try await world.service.deleteWorktree(item: topic)
        #expect(await git.remoteURL(named: "contributor", worktreePath: world.repository.path) != nil)
        try await world.service.deleteWorktree(item: other)
        #expect(await git.remoteURL(named: "contributor", worktreePath: world.repository.path) == nil)
    }

    @Test(arguments: ["existing", "changed", "push", "extra", "default", "branch"])
    func `remotes belonging to other work are kept`(reason: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let topic = try await checkout(in: world, existingRemote: reason == "existing")
        let path = world.repository.path
        if reason == "changed" {
            try await TestSupport.runGit(["remote", "set-url", "contributor", world.root + "/elsewhere"], in: path)
        } else if reason == "push" || reason == "extra" {
            try await TestSupport.runGit(
                ["remote", "set-url", reason == "push" ? "--push" : "--add", "contributor", world.root + "/elsewhere"],
                in: path,
            )
        } else if reason == "default" {
            try await TestSupport.runGit(["config", "remote.pushDefault", "contributor"], in: path)
        } else if reason == "branch" {
            try await TestSupport.runGit(["branch", "kept", "main"], in: path)
            try await TestSupport.runGit(["config", "branch.kept.remote", "contributor"], in: path)
        }

        try await world.service.deleteWorktree(item: topic)
        #expect(await git.remoteURL(named: "contributor", worktreePath: path) != nil)
        #expect(await git.remoteURL(named: "origin", worktreePath: path) != nil)
    }

    @Test
    func `refusing merge cleanup leaves the fork remote intact`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let topic = try await checkout(in: world)
        try "draft\n".write(toFile: topic.worktree.path + "/draft.txt", atomically: true, encoding: .utf8)

        #expect(try await world.service.cleanUpMergedWorktree(item: topic, baseRef: "main") == .dirty)
        #expect(await git.remoteURL(named: "contributor", worktreePath: world.repository.path) != nil)
    }

    @Test(arguments: ["fetch", "tagopt", "prune", "pushurl"])
    func `customised remote configuration is preserved`(key: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let topic = try await checkout(in: world)
        let value =
            switch key {
            case "fetch":
                "+refs/heads/topic:refs/remotes/contributor/topic"

            case "tagopt":
                "--no-tags"

            case "pushurl":
                world.root + "/github.com/contributor/repo"

            default:
                "true"
            }
        try await TestSupport.runGit(["config", "remote.contributor." + key, value], in: world.repository.path)

        try await world.service.deleteWorktree(item: topic)

        #expect(await git.remoteURL(named: "contributor", worktreePath: world.repository.path) != nil)
        #expect(try await TestSupport.runGit(
            ["config", "--get", "remote.contributor." + key], in: world.repository.path,
        )
        .standardOutput
        .trimmingCharacters(in: .whitespacesAndNewlines) == value)
    }

    // MARK: Private

    private let git: GitClient = .init(runner: FoundationProcessRunner())

    private func checkout(in world: World, existingRemote: Bool = false) async throws -> WorktreeItem {
        let path = world.repository.path
        let fork = world.root + "/github.com/contributor/repo"
        try await TestSupport.runGit(["clone", "-q", "--bare", path, fork], in: world.root)
        try await TestSupport.runGit(["branch", "topic", "main"], in: fork)
        let topic = item("topic", in: world)
        try await TestSupport.runGit(["worktree", "add", "-b", "topic", topic.worktree.path, "main"], in: path)
        if existingRemote {
            try await TestSupport.runGit(["remote", "add", "contributor", fork], in: path)
        }
        try await TestSupport.runGit(["remote", "add", "origin", fork], in: path)
        try await TestSupport.runGit(["config", "branch.topic.remote", fork], in: path)
        try await TestSupport.runGit(["config", "branch.topic.pushremote", fork], in: path)
        try await TestSupport.runGit(["config", "branch.topic.merge", "refs/heads/topic"], in: path)
        #expect(await world.service
            .forkRemote(worktreePath: topic.worktree.path, branch: "topic")?
            .remote == "contributor")
        return topic
    }

    private func item(_ branch: String, in world: World) -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: world.repository.name,
                repositoryPath: world.repository.path,
                branch: branch,
                path: world.root + "/" + branch,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: 0,
            hasUnread: false,
        )
    }
}
