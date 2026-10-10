@testable import AgentIDEData
import AgentIDEDomain
import Testing

// MARK: - AutofixGitHubTests

struct AutofixGitHubTests {
    @Test(arguments: [
        (#"{"permission":"write"}"#, true),
        (#"{"permission":"maintain"}"#, true),
        (#"{"permission":"custom","user":{"permissions":{"push":true}}}"#, true),
        (#"{"permission":"read","user":{"permissions":{"push":false}}}"#, false),
        (#"{"private":true}"#, false),
        ("unavailable", false),
    ])
    func `write permission must be explicitly verified by GitHub`(json: String, expected: Bool) async {
        let client = GitHubClient(runner: ReplyRunner(reply: json)) { true }
        #expect(await client.hasWriteAccess(login: "reviewer", repositoryPath: "/repo") == expected)
    }

    @Test
    func `all comment pages preserve author types and the latest identifier`() async throws {
        let json = """
        [{"data":{"node":{"comments":{"nodes":[
          {"id":"first","author":{"login":"human","type":"User"},"body":"Fix first"}
        ]}}}}, {"data":{"node":{"comments":{"nodes":[
          {"id":"latest","author":{"login":"copilot-pull-request-reviewer","type":"Bot"},"body":"Fix last"}
        ]}}}}]
        """
        let client = GitHubClient(runner: ReplyRunner(reply: json)) { true }
        let comments = try await client.reviewThreadComments(repositoryPath: "/repo", threadID: "thread")
        #expect(comments.map(\.id) == ["first", "latest"])
        #expect(comments.map(\.authorType) == ["User", "Bot"])
    }

    @Test
    func `real check fields retain the run identifier and incomplete required results`() async throws {
        let json = """
        [{"number":1,"title":"PR","url":"https://github.com/o/r/pull/1","headRefName":"feature",
        "headRefOid":"head","baseRefName":"main","headRepository":{"nameWithOwner":"fork/r"},
        "statusCheckRollup":[
          {"name":"test","status":"COMPLETED","conclusion":"FAILURE",
          "detailsUrl":"https://github.com/o/r/actions/runs/123/job/456"},
          {"name":"optional","status":"IN_PROGRESS","conclusion":""}
        ]}]
        """
        let summary = try #require(await GitHubClient.summaries(fromJSON: json) { _ in ["test"] }.first)
        #expect(summary.autofixChecks?.failures.first?.runID == "run:123")
        #expect(summary.headRepository == "fork/r")
        #expect(summary.retitled("Edited", body: "Body").autofixChecks == summary.autofixChecks)
        #expect(summary.awaitingChecks().autofixChecks == nil)
        let missing = try #require(await GitHubClient.summaries(fromJSON: json) { _ in ["test", "missing"] }.first)
        #expect(missing.autofixChecks?.isComplete == false)
    }
}

// MARK: - ReplyRunner

private struct ReplyRunner: ProcessRunner {
    let reply: String

    func run(
        _: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        ProcessResult(status: 0, standardOutput: reply, standardError: "")
    }
}
