@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - AutofixReadinessTests

struct AutofixReadinessTests {
    // MARK: Internal

    @Test(arguments: [true, false], ["idle", "working", "blocked", "unknown", "missing", "finished", "replaced"])
    func `initial fixes allow uncommitted work while completion still requires a clean worktree`(
        localReview: Bool,
        activity: String,
    ) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.paths.worktreesDirectory + "/feature"
        try await world.service.git.createWorktree(repository: world.repository, branch: "feature", at: path)
        try "Unrelated work".write(toFile: path + "/notes.txt", atomically: true, encoding: .utf8)
        let service = world.service(
            herdr: HerdrClient(
                runner: ReadinessRunner(activity: activity),
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
            ),
        )
        let head = try #require(await service.git.commitHash(of: "HEAD", worktreePath: path))
        let worktree = Worktree(
            repositoryName: "repo", repositoryPath: world.repository.path, branch: "feature", path: path,
        )
        let session = AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .idle)
        let item = WorktreeItem(
            worktree: worktree, session: session, isDirty: true, aheadOfUpstream: 0, hasUnread: false,
        )
        let group = RepositoryGroup(repository: world.repository, items: [item], defaultBranch: "main")
        let summary = PullRequestSummary(
            number: 1, title: "Change", url: "pr", headBranch: "feature", mergeable: "", reviewDecision: "", checks: "",
        )
        var state = PullRequestAutomation(repositoryPath: world.repository.path, number: 1, url: "pr")
        state.autofixLocalReviews = localReview
        state.autofixCI = localReview == false
        var target = try #require(SessionService.automationTarget(state, summary: summary, groups: [group]))
        #expect(await service.automationWaitReason(target: target, head: head) == Self.waits[activity])
        target.allowsUncommitted = false
        #expect(await service.automationWaitReason(target: target, head: head)
            == "Waiting for a clean worktree before accepting the fix")
        #expect(try String(contentsOfFile: path + "/notes.txt", encoding: .utf8) == "Unrelated work")
        try FileManager.default.removeItem(atPath: path + "/notes.txt")
        #expect(await service.automationWaitReason(target: target, head: head) == Self.waits[activity])
        #expect(await service.automationWaitReason(target: target, head: "changed")
            == "Waiting: the local commit changed or could not be read")
        try await TestSupport.runGit(["checkout", "--detach", head], in: path)
        #expect(await service.automationWaitReason(target: target, head: head) == "Check out feature before autofixing")
    }

    // MARK: Private

    private static let waits = [
        "working": "Your agent is working on something else. Autofix will wait until it finishes.",
        "blocked": "Waiting for you to answer the agent",
        "unknown": "Waiting for the agent's activity to be known",
        "missing": "Waiting: the agent session could not be found",
        "finished": "Waiting: the original agent session is no longer running",
        "replaced": "Waiting: the original agent session is no longer running",
    ]
}

// MARK: - ReadinessRunner

struct ReadinessRunner: ProcessRunner {
    let activity: String

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        let response =
            if activity == "missing" {
                #"{"result":{"snapshot":{"workspaces":[],"panes":[]}}}"#
            } else if arguments.contains("snapshot") {
                """
                {"result":{"snapshot":{"workspaces":[{"workspace_id":"workspace",
                "label":"\(activity == "replaced" ? "another-agent" : "agent")"}],
                "panes":[{"pane_id":"pane","workspace_id":"workspace","agent":"codex",
                "agent_status":"\(activity)"}]}}}
                """
            } else {
                """
                {"result":{"process_info":{"shell_pid":1,
                "foreground_process_group_id":\(activity == "finished" ? "1" : "2"),
                "foreground_processes":[{"name":"codex"}]}}}
                """
            }
        return ProcessResult(status: 0, standardOutput: response, standardError: "")
    }
}
