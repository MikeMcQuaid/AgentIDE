@testable import AgentIDEData
import AgentIDEDomain
import Testing

// MARK: - AutofixLogTests

struct AutofixLogTests {
    // MARK: Internal

    @Test(arguments: ["public", "private", "unknown"])
    func `required CI prompts include full output and only public links`(visibility: String) async throws {
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
        #expect(prompt.contains("Analyzing file 300"))
        #expect(prompt.contains("https://github.com/o/r/actions") == (visibility == "public"))
        #expect(prompt.contains("Analyzing file 201"))
        #expect(prompt.contains("2026-10-10T") == false)
        #expect(prompt.contains("optional") == false)
        #expect(await runner.commands == [
            ["gh", "api", "repos/{owner}/{repo}", "--cache", "60s"],
            ["gh", "run", "view", "--job", "11", "--log-failed"],
        ])
    }

    // MARK: Private

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Change",
            url: "https://github.com/o/r/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            headCommit: "head",
            autofixChecks: AutofixChecks(required: ["tests"], results: [
                AutofixCheck(
                    name: "tests",
                    status: "COMPLETED",
                    conclusion: "FAILURE",
                    runID: "run:1",
                    link: "https://github.com/o/r/actions/runs/1/job/11",
                ),
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
        let body = arguments.contains("api")
            ? (visibility == "unknown" ? "Unavailable" : "{\"private\":" + String(visibility == "private") + "}")
            : output
        return ProcessResult(status: 0, standardOutput: body, standardError: "")
    }

    // MARK: Private

    private let output: String
    private let visibility: String
}
