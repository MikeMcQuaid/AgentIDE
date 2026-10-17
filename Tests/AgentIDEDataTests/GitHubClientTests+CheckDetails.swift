@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - Check details

extension GitHubClientTests {
    @Test(arguments: [false, true])
    func `full check names preserve requirements`(unavailable: Bool) async throws {
        let summary = try #require(await GitHubClient(runner: CheckWorkflowRunner(unavailable: unavailable)) { true }
            .pullRequestSummary(repositoryPath: "/repo", number: 9) { _ in ["analyze"] })
        let checks = try #require(summary.checkDetails)
        #expect(checks.map(\.name) == ["analyze", "analyze"])
        #expect(checks.allSatisfy { $0.requirement == .required })
        #expect(checks.map(\.displayName) == (unavailable
                ? ["CI / analyze", "CI / analyze"]
                : ["GitHub Actions CI / analyze (pull_request)", "Release / analyze (push)"]))
        #expect(checks.map(\.statusDescription) == ["Successful", "Running"])
        #expect(summary.autofixChecks?.required == ["analyze"])
        let cached = try JSONDecoder().decode(PullRequestSummary.self, from: JSONEncoder().encode(summary))
        #expect(cached.checkDetails == checks)
    }

    @Test
    func `check details retain optional jobs and unreported requirements`() async throws {
        let json = """
        [{"number": 9, "title": "Work", "url": "https://github.com/o/r/pull/9",
          "headRefName": "b", "baseRefName": "main", "statusCheckRollup": [
            {"name": "build", "status": "COMPLETED", "conclusion": "FAILURE",
             "startedAt": "2026-10-17T10:00:00Z", "completedAt": "2026-10-17T10:02:03Z",
             "detailsUrl": "https://github.com/o/r/actions/runs/1/job/2"},
            {"name": "tests", "status": "IN_PROGRESS", "conclusion": "",
             "startedAt": "2026-10-17T10:01:00Z", "completedAt": "0001-01-01T00:00:00Z",
             "detailsUrl": "https://github.com/o/r/actions/runs/1/job/3"},
            {"context": "external", "state": "SUCCESS", "targetUrl": "https://ci.example.com/build"}
          ]}]
        """
        let summary = try #require(await GitHubClient.summaries(fromJSON: json) { _ in ["build", "missing"] }.first)
        let checks = try #require(summary.checkDetails)
        let build = try #require(checks.first { $0.name == "build" })
        #expect(build.requirement == .required)
        #expect(build.duration == 123)
        #expect(build.jobID == 2)
        #expect(build.canReadLog)
        #expect(build.displayName == "build")
        let running = try #require(checks.first { $0.name == "tests" })
        #expect(running.requirement == .optional)
        #expect(running.isComplete == false)
        #expect(running.duration == nil)
        #expect(running.canReadLog == false)
        #expect(checks.first { $0.name == "missing" }?.status == "EXPECTED")
        #expect(checks.first { $0.name == "external" }?.link == "https://ci.example.com/build")
        #expect(checks.first { $0.name == "external" }?.duration == nil)
        #expect(summary.retitled("New", body: "").checkDetails == checks)
        #expect(summary.awaitingChecks().checkDetails == nil)
        let cached = try JSONDecoder().decode(PullRequestSummary.self, from: JSONEncoder().encode(summary))
        #expect(cached.checkDetails == checks)
        let unknown = try #require(await GitHubClient.summaries(fromJSON: json) { _ in nil }.first)
        #expect(unknown.checkDetails?.allSatisfy { $0.requirement == .unknown } == true)
    }
}

// MARK: - CheckWorkflowRunner

private struct CheckWorkflowRunner: ProcessRunner {
    let unavailable: Bool

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        if arguments.starts(with: ["gh", "pr", "view", "9", "--json"]) {
            return ProcessResult(
                status: 0,
                standardOutput: """
                {"number": 9, "title": "Work", "url": "https://github.com/o/r/pull/9",
                 "headRefName": "b", "baseRefName": "main", "statusCheckRollup": [
                   {"name": "analyze", "workflowName": "CI", "status": "COMPLETED", "conclusion": "SUCCESS",
                    "detailsUrl": "https://github.com/o/r/actions/runs/1/job/2"},
                   {"name": "analyze", "workflowName": "CI", "status": "IN_PROGRESS", "conclusion": "",
                    "detailsUrl": "https://github.com/o/r/actions/runs/3/job/4"}
                 ]}
                """,
                standardError: "",
            )
        }
        #expect(arguments == ["gh", "pr", "checks", "9", "--json", "name,link,workflow,event"])
        return ProcessResult(
            status: unavailable ? 1 : 0,
            standardOutput: unavailable ? "" : """
            [{"name": "analyze", "link": "https://github.com/o/r/actions/runs/3/job/4",
              "workflow": "Release", "event": "push"},
             {"name": "analyze", "link": "https://github.com/o/r/actions/runs/1/job/2",
              "workflow": "GitHub Actions CI", "event": "pull_request"}]
            """,
            standardError: unavailable ? "Unavailable" : "",
        )
    }
}
