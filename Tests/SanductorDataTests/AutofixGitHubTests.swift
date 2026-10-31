import Foundation
@testable import SanductorData
import SanductorDomain
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
    func `unreadable branch protection still exposes every reported CI result`() async throws {
        let directory = try TestSupport.temporaryDirectory("unknown-checks")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let store = MetadataStore(file: directory + "/state.json")
        let github = GitHubClient(runner: ReplyRunner(reply: "")) { false }
        let pullRequests = PullRequestStore(github: github, store: store)
        let json = """
        [{"number":1,"title":"PR","url":"pr","headRefName":"feature","baseRefName":"main",
        "statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]}]
        """
        let unknown = try #require(await GitHubClient.summaries(
            fromJSON: json, requiredChecks: pullRequests.requiredChecksReader(repositoryPath: "/repo"),
        )
        .first)
        #expect(unknown.autofixChecks?.failures.count == 1)
        #expect(unknown.checks == "FAILURE")
        store.update { $0.requiredChecksCache["required-checks#/repo#main"] = [] }
        let known = try #require(await GitHubClient.summaries(
            fromJSON: json, requiredChecks: pullRequests.requiredChecksReader(repositoryPath: "/repo"),
        )
        .first)
        #expect(known.autofixChecks?.isComplete == true)
        #expect(known.autofixChecks?.failures.count == 1)
    }

    @Test
    func `rerunning a workflow gives its failed jobs fresh delivery identities`() async throws {
        let json = """
        [{"number":1,"title":"PR","url":"pr","headRefName":"feature","statusCheckRollup":[
          {"name":"test","status":"COMPLETED","conclusion":"FAILURE",
          "detailsUrl":"https://github.com/o/r/actions/runs/123/job/456"}
        ]}]
        """
        let requiredChecks: GitHubClient.RequiredChecksReader = { _ in nil }
        let first = try #require(await GitHubClient.summaries(fromJSON: json, requiredChecks: requiredChecks)
            .first?
            .autofixChecks?
            .failures
            .first)
        let rerun = try #require(await GitHubClient.summaries(
            fromJSON: json.replacing("job/456", with: "job/789"), requiredChecks: requiredChecks,
        )
        .first?
        .autofixChecks?
        .failures
        .first)
        #expect(first.runID != rerun.runID)
    }

    @Test(arguments: ["https://ci.example/build", "https://ci.example/runs/123/job/456"])
    func `external failures without Actions identifiers trigger once per head and rerun`(link: String) async throws {
        let json = """
        [{"number":1,"title":"PR","url":"pr","headRefName":"feature","headRefOid":"head",
        "statusCheckRollup":[{"name":"external","status":"COMPLETED","conclusion":"FAILURE",
        "startedAt":"2026-01-01T00:00:00Z","detailsUrl":"\(link)"}]}]
        """
        let requiredChecks: GitHubClient.RequiredChecksReader = { _ in nil }
        let first = try #require(await GitHubClient.summaries(fromJSON: json, requiredChecks: requiredChecks).first)
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixCI = true
        let candidate = try #require(AutofixCandidate.checks(summary: first, state: state))
        #expect(candidate.text.contains("external: FAILURE"))
        state.handledEvents = candidate.events
        #expect(AutofixCandidate.checks(summary: first, state: state) == nil)
        for changed in [
            json.replacing("2026-01-01", with: "2026-01-02"), json.replacing("\"head\"", with: "\"new-head\""),
        ] {
            let summary = try #require(await GitHubClient.summaries(
                fromJSON: changed, requiredChecks: requiredChecks,
            )
            .first)
            #expect(AutofixCandidate.checks(summary: summary, state: state) != nil)
        }
        let undated = json.replacing("\"startedAt\":\"2026-01-01T00:00:00Z\",", with: "")
        let summary = try #require(await GitHubClient.summaries(
            fromJSON: undated, requiredChecks: requiredChecks,
        )
        .first)
        #expect(AutofixCandidate.checks(summary: summary, state: state) != nil)
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
        #expect(summary.autofixChecks?.results.first?.runID == "job:456")
        #expect(summary.autofixChecks?.isComplete == false)
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
