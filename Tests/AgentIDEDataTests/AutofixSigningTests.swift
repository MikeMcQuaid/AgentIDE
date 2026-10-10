@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - AutofixSigningTests

struct AutofixSigningTests {
    @Test
    func `the app signs only new fix commits and pushes their unchanged code to the same PR`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let fork = world.root + "/fork.git"
        try await TestSupport.runGit(["clone", "--bare", path, fork], in: world.root)
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: path)
        try await TestSupport.runGit(["push", fork, "feature"], in: path)
        try await TestSupport.runGit(["remote", "add", "contributor", "https://github.com/contributor/repo"], in: path)
        try await TestSupport.runGit(["config", "branch.feature.remote", "contributor"], in: path)
        try ".signing-key*\n.allowed-signers\n"
            .write(toFile: path + "/.git/info/exclude", atomically: true, encoding: .utf8)
        try await BranchStackIntegrationTests.signable(path)
        let head = try #require(await world.service.git.tip(of: "HEAD", worktreePath: path))
        try await BranchStackIntegrationTests.commit("Fix", in: path)
        let commit = try #require(await world.service.git.tip(of: "HEAD", worktreePath: path))
        let service = world.service(
            herdr: HerdrClient(
                runner: ReadinessRunner(activity: "idle"),
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
            ),
            git: GitClient(runner: AutofixPushRunner(fork: fork)),
        )
        let target = AutofixDriver.Target(
            worktree: Worktree(repositoryName: "repo", repositoryPath: path, branch: "feature", path: path),
            session: AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .idle),
        )
        let summary = PullRequestSummary(
            number: 1,
            title: "Fix",
            url: "pr",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: head,
            headRepository: "contributor/repo",
        )
        let pushed = try await service.pushAutofix(target: target, summary: summary, commit: commit)
        let signed = try #require(await service.git.tip(of: "HEAD", worktreePath: path))
        #expect(signed != commit)
        #expect(pushed == signed)
        #expect(await service.git.allCommitsSigned(worktreePath: path, range: head + ".." + signed))
        #expect(await service.git.commitHash(of: signed + "^{tree}", worktreePath: path)
            == service.git.commitHash(of: commit + "^{tree}", worktreePath: path))
        #expect(await service.git.tip(of: "feature", worktreePath: fork) == signed)
        #expect(await service.git.tip(of: "main", worktreePath: path) == head)
    }
}

// MARK: - AutofixPushRunner

private struct AutofixPushRunner: ProcessRunner {
    let fork: String

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        let redirected = arguments.contains("push")
            ? arguments.map { $0 == "https://github.com/contributor/repo" ? fork : $0 } : arguments
        return try await FoundationProcessRunner().run(
            redirected, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
