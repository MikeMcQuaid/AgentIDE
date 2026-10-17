@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

extension GitHubClientTests {
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
