@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - AutofixLogTests

struct AutofixLogTests {
    // MARK: Internal

    @Test(arguments: ["public", "private", "unknown"])
    func `required CI prompts condense complete logs and include only public links`(visibility: String) async throws {
        var lines = (1 ... 600).map { "analyze\tAnalyze\t2026-10-10T11:15:00Z Analyzing file " + String($0) }
        lines[99] = "analyze\tAnalyze\t2026-10-10T11:15:00Z Sources/A.swift:1:1: error: Unused import"
        lines[199] = "tests\tTest\t2026-10-10T11:15:00Z ✘ Test recorded an issue: Expectation failed: submitted"
        let runner = LogRunner(output: lines.joined(separator: "\n"), visibility: visibility)
        let summary = summary()
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: summary.url)
        state.autofixCI = true
        let candidate = try #require(AutofixCandidate.checks(summary: summary, state: state))
        let prompt = try await GitHubClient(runner: runner).autofixPrompt(
            candidate, summary: summary, repositoryPath: "/repo",
        )
        #expect(prompt.contains("Sources/A.swift:1:1: error: Unused import"))
        #expect(prompt.contains("Expectation failed: submitted"))
        #expect(prompt.contains("Analyzing file 99"))
        #expect(prompt.contains("Analyzing file 300") == false)
        #expect(prompt.contains("lines cut"))
        #expect(prompt.contains("https://github.com/o/r/actions") == (visibility == "public"))
        #expect(prompt.contains("Analyzing file 201") == false)
        #expect(prompt.contains("2026-10-10T") == false)
        #expect(prompt.contains("optional") == false)
        #expect(await runner.commands == [
            ["gh", "api", "repos/{owner}/{repo}", "--cache", "60s"],
            ["gh", "api", "repos/{owner}/{repo}/actions/jobs/11/logs"],
        ])
    }

    @Test
    func `large failure logs are bounded while both ends remain readable`() async throws {
        let log = "error: first diagnostic\n"
            + String(repeating: "error: " + String(repeating: "x", count: 200) + "\n", count: 10_000)
            + "error: final diagnostic"
        let runner = LogRunner(output: log, visibility: "private")
        let summary = summary()
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: summary.url)
        state.autofixCI = true
        let candidate = try #require(AutofixCandidate.checks(summary: summary, state: state))
        let prompt = try await GitHubClient(runner: runner).autofixPrompt(
            candidate, summary: summary, repositoryPath: "/repo",
        )
        #expect(prompt.utf8.count < 66_000)
        #expect(prompt.contains("first diagnostic"))
        #expect(prompt.contains("final diagnostic"))
        #expect(prompt.contains("log shortened"))
    }

    @Test
    func `the log budget is shared across all required failures`() async throws {
        let log = "error: first diagnostic\n"
            + String(repeating: "é", count: 200_000) + "\nerror: final diagnostic"
        let runner = LogRunner(output: log, visibility: "private")
        let summary = summary(requiredJobs: 10)
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: summary.url)
        state.autofixCI = true
        let candidate = try #require(AutofixCandidate.checks(summary: summary, state: state))
        let prompt = try await GitHubClient(runner: runner).autofixPrompt(
            candidate, summary: summary, repositoryPath: "/repo",
        )
        #expect(prompt.utf8.count < 263_000)
        #expect(prompt.components(separatedBy: "first diagnostic").count == 11)
        #expect(prompt.components(separatedBy: "final diagnostic").count == 11)
    }

    // MARK: Private

    private func summary(requiredJobs: Int = 1) -> PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Change",
            url: "https://github.com/o/r/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            headCommit: "head",
            autofixChecks: AutofixChecks(required: Set((1 ... requiredJobs).map { "tests " + String($0) }), results:
                (1 ... requiredJobs).map { index in
                    AutofixCheck(
                        name: "tests " + String(index),
                        status: "COMPLETED",
                        conclusion: "FAILURE",
                        runID: "run:1",
                        link: "https://github.com/o/r/actions/runs/1/job/" + String(10 + index),
                    )
                } + [
                    AutofixCheck(
                        name: "optional",
                        status: "COMPLETED",
                        conclusion: "FAILURE",
                        runID: "run:2",
                        link: "https://github.com/o/r/actions/runs/2/job/22",
                    ),
                ]),
        )
    }
}

// MARK: - LogRunner

private actor LogRunner: ProcessRunner {
    // MARK: Lifecycle

    init(output: String, visibility: String) {
        self.output = output
        self.visibility = visibility
    }

    // MARK: Internal

    var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        let body: String =
            if arguments.contains("repos/{owner}/{repo}") {
                visibility == "unknown" ? "Unavailable" : "{\"private\":" + String(visibility == "private") + "}"
            } else if arguments.last?.hasSuffix("/logs") == true {
                output
            } else {
                "tests\tTest\t2026-10-10T11:15:00Z Tests started; failure is outside the recognised step"
            }
        return ProcessResult(status: 0, standardOutput: body, standardError: "")
    }

    // MARK: Private

    private let output: String
    private let visibility: String
}
