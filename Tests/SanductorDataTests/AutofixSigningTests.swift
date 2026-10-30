import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

// MARK: - AutofixSigningTests

struct AutofixSigningTests {
    // MARK: Internal

    @Test(arguments: ["none", "signing", "transport"])
    func `the app signs only new fix commits and pushes their unchanged code to the same PR`(
        failure: String,
    ) async throws {
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
        let runner = AutofixPushRunner(fork: fork, fails: failure == "transport")
        let service = world.service(
            herdr: HerdrClient(
                runner: ReadinessRunner(activity: "idle"),
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
            ),
            git: GitClient(runner: runner),
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
        let pushing = try await retryCommit(failure, service: service, target: target, summary: summary, commit: commit)
        let pushed = try await service.pushAutofix(target: target, summary: summary, commit: pushing)
        let signed = try #require(await service.git.tip(of: "HEAD", worktreePath: path))
        #expect(signed != commit)
        #expect(pushed == signed)
        #expect(await service.git.allCommitsSigned(worktreePath: path, range: head + ".." + signed))
        #expect(await service.git.commitHash(of: signed + "^{tree}", worktreePath: path)
            == service.git.commitHash(of: commit + "^{tree}", worktreePath: path))
        #expect(await service.git.tip(of: "feature", worktreePath: fork) == signed)
        #expect(await service.git.tip(of: "main", worktreePath: path) == head)
    }

    // MARK: Private

    private func retryCommit(
        _ failure: String,
        service: SessionService,
        target: AutofixDriver.Target,
        summary: PullRequestSummary,
        commit: String,
    ) async throws -> String {
        let path = target.worktree.path
        var pushing = commit
        if failure == "signing" {
            try await TestSupport.runGit(["config", "gpg.ssh.program", "/usr/bin/false"], in: path)
            await #expect(throws: (any Error).self) {
                try await service.pushAutofix(target: target, summary: summary, commit: commit)
            }
            #expect(await service.git.tip(of: "HEAD", worktreePath: path) == commit)
            #expect(await service.git.currentBranch(worktreePath: path) == "feature")
            #expect(await service.git.isDirty(worktreePath: path) == false)
            try await TestSupport.runGit(["config", "gpg.ssh.program", "ssh-keygen"], in: path)
        } else if failure == "transport" {
            do {
                _ = try await service.pushAutofix(target: target, summary: summary, commit: commit)
                Issue.record("Expected a transport failure")
            } catch let error as AutofixPushError {
                pushing = error.commit
                #expect(pushing != commit)
                #expect(await service.git.tip(of: "HEAD", worktreePath: path) == pushing)
            }
        }
        return pushing
    }
}

// MARK: - AutofixPushRunner

private actor AutofixPushRunner: ProcessRunner {
    // MARK: Lifecycle

    init(fork: String, fails: Bool) {
        self.fork = fork
        self.fails = fails
    }

    // MARK: Internal

    let fork: String
    var fails: Bool

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.contains("push"), fails {
            fails = false
            return ProcessResult(status: 1, standardOutput: "", standardError: "Connection lost")
        }
        let redirected = arguments.contains("push")
            ? arguments.map { $0 == "https://github.com/contributor/repo" ? fork : $0 } : arguments
        return try await FoundationProcessRunner().run(
            redirected, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
