import AgentIDEData
import AgentIDEDomain
@testable import AgentIDERemote
import Foundation
import Testing

struct RemoteWorktreeTests {
    @Test
    func `the phone reads exact branches and local changes without remote access`() async throws {
        let root = try TestSupport.temporaryDirectory("phone-status")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo ' $(touch unwanted)"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["switch", "-c", "Feature/雪_login_fix"], in: path)
        try await TestSupport.runGit(["config", "core.fsmonitor", "touch " + root + "/fsmonitor-ran"], in: path)
        try "new".write(toFile: path + "/new\n# branch.head wrong", atomically: true, encoding: .utf8)
        let result = try await TestSupport.run([
            "/bin/sh", "-c",
            SSHConfiguration().command(RemoteHerdr.worktreeStatusCommand(paths: [path, root + "/missing"])),
        ])
        #expect(result.standardOutput == "Feature/雪_login_fix\t\t\t1\n\n")
        let statuses = RemoteHerdr.parseWorktreeStatuses(result.standardOutput, paths: [path, root + "/missing"])
        let status = try #require(statuses[path])
        #expect(status.branch == "Feature/雪_login_fix")
        #expect(status.isDirty)
        #expect(status.summary == "±")
        #expect(statuses.count == 1)
        #expect(await GitClient(runner: FoundationProcessRunner()).isDirty(worktreePath: path))
        #expect(FileManager.default.fileExists(atPath: root + "/fsmonitor-ran") == false)
        #expect(FileManager.default.fileExists(atPath: path + "/unwanted") == false)
    }

    @Test
    func `upstream drift is read from local refs without fetching`() async throws {
        let path = try TestSupport.temporaryDirectory("phone-upstream")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["branch", "upstream", "main"], in: path)
        try await TestSupport.runGit(["branch", "--set-upstream-to=upstream", "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Ahead"], in: path)
        try await TestSupport.runGit(["switch", "upstream"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Behind"], in: path)
        try await TestSupport.runGit(["switch", "main"], in: path)
        let result = try await TestSupport.run(RemoteHerdr.worktreeStatusCommand(paths: [path]))
        #expect(result.standardOutput == "main\t1\t1\t0\n")
        let status = try #require(RemoteHerdr.parseWorktreeStatuses(result.standardOutput, paths: [path])[path])
        #expect(status.branch == "main")
        #expect(status.summary == "↑1 ↓1")
        #expect(status.isDirty == false)
    }

    @Test
    func `large change sets send only the sidebar summary`() async throws {
        let path = try TestSupport.temporaryDirectory("phone-large-status")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let blob = try await TestSupport.runGit(["rev-parse", "HEAD:README.md"], in: path)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try (0 ..< 10_000)
            .map { "100644 " + blob + "\tgenerated/file-" + String($0) + "-雪\n" }
            .joined()
            .write(toFile: path + "/.git/status-fixture", atomically: true, encoding: .utf8)
        try await TestSupport.run([
            "/bin/sh", "-c",
            "git --no-optional-locks -c core.fsmonitor=false update-index --index-info < .git/status-fixture",
        ], in: path)
        let raw = try await TestSupport.runGit(GitWorktreeStatus.arguments + ["--branch"], in: path)
        #expect(raw.standardOutput.utf8.count > 1_048_576)
        let result = try await TestSupport.run(RemoteHerdr.worktreeStatusCommand(paths: [path]))
        #expect(result.standardOutput.utf8.count == "main\t\t\t1\n".utf8.count)
        let status = try #require(RemoteHerdr.parseWorktreeStatuses(result.standardOutput, paths: [path])[path])
        #expect(status.branch == "main")
        #expect(status.isDirty)
    }

    @Test
    func `a failed Git reading does not shift or hide other worktrees`() async throws {
        let root = try TestSupport.temporaryDirectory("phone-broken-status")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let broken = root + "/broken"
        let healthy = root + "/healthy"
        try await TestSupport.makeRepository(at: broken)
        try await TestSupport.makeRepository(at: healthy)
        try "broken index".write(toFile: broken + "/.git/index", atomically: true, encoding: .utf8)
        let paths = [root + "/missing", broken, healthy]
        let result = try await TestSupport.run(RemoteHerdr.worktreeStatusCommand(paths: paths))
        #expect(result.standardOutput == "\n\nmain\t\t\t0\n")
        let statuses = RemoteHerdr.parseWorktreeStatuses(result.standardOutput, paths: paths)
        #expect(statuses.count == 1)
        #expect(statuses[healthy]?.branch == "main")
        #expect(statuses[healthy]?.isDirty == false)
    }

    @Test(arguments: [false, true])
    func `unborn and detached branches keep unknown upstream counts`(detached: Bool) async throws {
        let path = try TestSupport.temporaryDirectory("phone-head")
        defer { try? FileManager.default.removeItem(atPath: path) }
        if detached {
            try await TestSupport.makeRepository(at: path)
            try await TestSupport.runGit(["switch", "--detach", "HEAD"], in: path)
        } else {
            try await TestSupport.runGit(["init", "-q", "-b", "main"], in: path)
        }
        let result = try await TestSupport.run(RemoteHerdr.worktreeStatusCommand(paths: [path]))
        let status = try #require(RemoteHerdr.parseWorktreeStatuses(result.standardOutput, paths: [path])[path])
        #expect(status.branch == (detached ? nil : "main"))
        #expect(status.aheadOfUpstream == nil)
        #expect(status.behindUpstream == nil)
        #expect(status.isDirty == false)
    }
}
