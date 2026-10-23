@testable import AgentIDEData
import Testing

extension GitHubClientTests {
    @Test(arguments: [
        "", "https://github.com/o/r/issues/24324\nhttps://github.com/other/repo/issues/7\n"
            + "https://github.com/o/r/issues/24324\n",
    ])
    func `closing issues are assigned once by their own repository URLs`(output: String) async throws {
        let runner = IssueAssignmentRunner(output: output)
        let client = GitHubClient(runner: runner) { true }
        try await client.assignClosingIssues(repositoryPath: "/repo", pullRequestURL: "https://github.com/o/r/pull/42")
        let commands = await runner.commands
        #expect(commands.first == [
            "gh", "pr", "view", "https://github.com/o/r/pull/42", "--json", "closingIssuesReferences",
            "--jq", ".closingIssuesReferences[].url",
        ])
        #expect(Array(commands.dropFirst()) == (output.isEmpty ? [] : [
            ["gh", "issue", "edit", "https://github.com/o/r/issues/24324", "--add-assignee", "@me"],
            ["gh", "issue", "edit", "https://github.com/other/repo/issues/7", "--add-assignee", "@me"],
        ]))
    }

    @Test(arguments: ["view", "https://github.com/o/r/issues/1"])
    func `assignment failures surface after trying every available issue`(failing: String) async {
        let runner = IssueAssignmentRunner(
            output: "https://github.com/o/r/issues/1\nhttps://github.com/o/r/issues/2\n",
            failing: failing,
        )
        let client = GitHubClient(runner: runner) { true }
        await #expect(throws: (any Error).self) {
            try await client.assignClosingIssues(
                repositoryPath: "/repo",
                pullRequestURL: "https://github.com/o/r/pull/42",
            )
        }
        #expect(await runner.commands.count == (failing == "view" ? 1 : 3))
    }
}

// MARK: - IssueAssignmentRunner

private actor IssueAssignmentRunner: ProcessRunner {
    // MARK: Lifecycle

    init(output: String, failing: String = "") {
        self.output = output
        self.failing = failing
    }

    // MARK: Internal

    let output: String
    let failing: String
    var commands: [[String]] = []

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        #expect(workingDirectory == "/repo")
        commands.append(arguments)
        return ProcessResult(
            status: arguments.contains(failing) ? 1 : 0,
            standardOutput: arguments.contains("view") ? output : "",
            standardError: arguments.contains(failing) ? "Assignment unavailable" : "",
        )
    }
}
