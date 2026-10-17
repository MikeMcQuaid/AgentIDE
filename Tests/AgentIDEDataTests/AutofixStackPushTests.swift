@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - AutofixStackPushTests

struct AutofixStackPushTests {
    @Test(arguments: [false, true])
    func `autofix updates published children through signing without publishing local branches`(
        signed: Bool,
    ) async throws {
        let fixture = try await AutofixStackFixture(signed: signed)
        defer { fixture.world.tearDown() }
        let path = fixture.world.repository.path
        let git = fixture.service.git
        let before = try #require(await git.tip(of: "upper", worktreePath: path))

        let pushed = try await fixture.service.pushAutofix(
            target: fixture.target, summary: fixture.summary, commit: fixture.commit,
        )

        #expect(await git.tip(of: "lower", worktreePath: fixture.remote) == pushed)
        #expect(await git.tip(of: "upper", worktreePath: fixture.remote) == git.tip(of: "upper", worktreePath: path))
        #expect(await git.isAncestor(pushed, of: "upper", worktreePath: fixture.remote))
        #expect(await git.sameTree(before, "upper", worktreePath: path))
        #expect(await git.refExists(worktreePath: fixture.remote, ref: "refs/heads/unpublished") == false)
        #expect(await git.currentBranch(worktreePath: path) == "lower")
        #expect(await git.sameTree(fixture.commit, pushed, worktreePath: path))
        #expect((pushed == fixture.commit) == signed)
        #expect(fixture.service.store.load().pendingChecks.keys.contains { $0.hasSuffix("#upper") })
    }

    @Test
    func `a moved autofix remote refuses before pushing children`() async throws {
        let fixture = try await AutofixStackFixture(signed: true)
        defer { fixture.world.tearDown() }
        let before = await fixture.service.git.tip(of: "upper", worktreePath: fixture.remote)
        try await TestSupport.runGit(["update-ref", "refs/heads/lower", "upper"], in: fixture.remote)

        await #expect(throws: AutofixPushError.self) {
            try await fixture.service.pushAutofix(
                target: fixture.target, summary: fixture.summary, commit: fixture.commit,
            )
        }
        #expect(await fixture.service.git.tip(of: "upper", worktreePath: fixture.remote) == before)
        #expect(await fixture.service.git.tip(of: "lower", worktreePath: fixture.remote) == before)
    }

    @Test(arguments: [false, true])
    func `autofix on an upper branch never publishes lower branches`(parentMoved: Bool) async throws {
        let fixture = try await AutofixStackFixture(signed: true)
        defer { fixture.world.tearDown() }
        let path = fixture.world.repository.path
        let git = fixture.service.git
        if parentMoved {
            try await BranchStackIntegrationTests.signedCommit("unreviewed lower work", in: path)
        }
        let lower = try #require(await git.tip(of: "lower", worktreePath: path))
        try await TestSupport.runGit(["checkout", "upper"], in: path)
        let commit = try #require(await git.tip(of: "upper", worktreePath: path))
        let target = AutofixDriver.Target(
            worktree: StackedSessionIntegrationTests.worktree("upper", at: path, in: fixture.world.repository),
            session: fixture.target.session,
        )
        let summary = await PullRequestSummary(
            number: 2,
            title: "Upper",
            url: "pr",
            headBranch: "upper",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: git.tip(of: "upper", worktreePath: fixture.remote),
            headRepository: "owner/repo",
        )
        #expect(await fixture.service.stack(for: target.worktree).branches == ["lower", "upper", "unpublished"])

        if parentMoved {
            await #expect(throws: AutofixPushError.self) {
                try await fixture.service.pushAutofix(target: target, summary: summary, commit: commit)
            }
            #expect(await git.tip(of: "upper", worktreePath: fixture.remote) == summary.headCommit)
        } else {
            #expect(try await fixture.service.pushAutofix(target: target, summary: summary, commit: commit) == commit)
            #expect(await git.tip(of: "upper", worktreePath: fixture.remote) == commit)
        }
        #expect(await git.tip(of: "lower", worktreePath: fixture.remote) == fixture.head)
        #expect(await git.tip(of: "lower", worktreePath: path) == lower)
        #expect(await git.refExists(worktreePath: fixture.remote, ref: "refs/heads/unpublished") == false)
        #expect(fixture.service.store.load().pendingChecks.keys.contains { $0.hasSuffix("#lower") } == false)
    }

    @Test
    func `a standalone fork keeps its pinned autofix destination`() async throws {
        let fixture = try await AutofixStackFixture(signed: false, stacked: false)
        defer { fixture.world.tearDown() }
        let path = fixture.world.repository.path
        try await TestSupport.runGit(["remote", "rename", "origin", "contributor"], in: path)

        let pushed = try await fixture.service.pushAutofix(
            target: fixture.target, summary: fixture.summary, commit: fixture.commit,
        )

        #expect(await fixture.service.git.tip(of: "lower", worktreePath: fixture.remote) == pushed)
        #expect(await fixture.service.git.branchRemote(worktreePath: path, branch: "lower") == "contributor")
    }
}

// MARK: - AutofixStackFixture

private struct AutofixStackFixture {
    // MARK: Lifecycle

    init(signed: Bool, stacked: Bool = true) async throws {
        world = try await World.make()
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        try await BranchStackIntegrationTests.signedCommit("base", in: path)
        remote = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, remote], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", remote], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["checkout", "-b", "lower"], in: path)
        try await BranchStackIntegrationTests.signedCommit("lower", in: path)
        try await TestSupport.runGit(["push", "--set-upstream", "origin", "lower"], in: path)
        head = try #require(await world.service.git.tip(of: "lower", worktreePath: path))
        if signed {
            try await BranchStackIntegrationTests.signedCommit("fix", in: path)
        } else {
            try await BranchStackIntegrationTests.commit("fix", in: path)
        }
        commit = try #require(await world.service.git.tip(of: "lower", worktreePath: path))
        if stacked {
            try await TestSupport.runGit(["checkout", "-b", "upper", "lower"], in: path)
            try await BranchStackIntegrationTests.signedCommit("upper", in: path)
            try await TestSupport.runGit(["push", "--set-upstream", "origin", "upper"], in: path)
            try await BranchStackIntegrationTests.signedCommit("upper update", in: path)
            try await TestSupport.runGit(["checkout", "-b", "unpublished", "upper"], in: path)
            try await BranchStackIntegrationTests.commit("unpublished", in: path)
            try await TestSupport.runGit(["checkout", "lower"], in: path)
        }
        try await TestSupport.runGit(
            ["config", "remote.origin.pushurl", "https://github.com/owner/repo"], in: path,
        )
        let runner = AutofixStackRunner(remote: remote)
        service = SessionService(
            paths: world.paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true),
            github: GitHubClient(runner: runner),
            transcripts: world.service.transcripts,
            spool: world.service.spool,
            store: world.service.store,
            runners: [],
        )
    }

    // MARK: Internal

    let world: World
    let service: SessionService
    let remote: String
    let commit: String
    let head: String

    var target: AutofixDriver.Target {
        AutofixDriver.Target(
            worktree: StackedSessionIntegrationTests.worktree("lower", at: world.repository.path, in: world.repository),
            session: AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .idle),
        )
    }

    var summary: PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Lower",
            url: "pr",
            headBranch: "lower",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: head,
            headRepository: "owner/repo",
        )
    }
}

// MARK: - AutofixStackRunner

private struct AutofixStackRunner: ProcessRunner {
    let remote: String

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.first == "gh" {
            return ProcessResult(status: 0, standardOutput: "WRITE", standardError: "")
        }
        if arguments.contains("snapshot") {
            return ProcessResult(
                status: 0,
                standardOutput: """
                {"result":{"snapshot":{"workspaces":[{"workspace_id":"workspace","label":"agent"}],
                "panes":[{"pane_id":"pane","workspace_id":"workspace","agent":"codex","agent_status":"idle"}]}}}
                """,
                standardError: "",
            )
        }
        return try await FoundationProcessRunner().run(
            arguments.contains("push") ? arguments.map { argument in
                argument == "origin" || argument == "https://github.com/owner/repo" ? remote : argument
            } : arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            outputLimit: outputLimit,
        )
    }
}
