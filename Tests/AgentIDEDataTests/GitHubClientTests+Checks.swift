@testable import AgentIDEData
import Testing

/// Which checks decide a rollup: the ones the base branch requires,
/// when it requires any.
extension GitHubClientTests {
    @Test
    func `only the checks a branch requires decide its rollup`() async throws {
        let json = """
        [{"number": 9, "title": "Fix", "url": "https://github.com/o/r/pull/9",
          "headRefName": "b", "baseRefName": "main", "mergeable": "", "reviewDecision": "",
          "statusCheckRollup": [
            {"__typename": "CheckRun", "name": "build", "state": "COMPLETED", "conclusion": "SUCCESS",
             "detailsUrl": "https://ci/build"},
            {"__typename": "CheckRun", "name": "nightly", "state": "COMPLETED", "conclusion": "FAILURE",
             "detailsUrl": "https://ci/nightly"},
            {"__typename": "StatusContext", "context": "lint", "state": "SUCCESS"}
          ]}]
        """
        // A failing check nobody requires leaves the rollup green,
        // with the failure still there to open. The rules asked for
        // are the base branch's: any other answer would be pending.
        let green = try #require(await GitHubClient.summaries(fromJSON: json) { base in
            base == "main" ? ["build", "lint"] : ["never-reported"]
        }.first)
        #expect(green.checks == "SUCCESS")
        // Counted for the help, never offered to open or copy.
        #expect(green.failingCheckLinks.isEmpty)
        #expect(green.optionalFailures == 1)
        #expect(green.checksDescription == "passing; 1 optional check failing")

        // A required check GitHub has yet to hear from is waited on.
        let waiting = try #require(await GitHubClient.summaries(fromJSON: json) { _ in ["build", "docs"] }.first)
        #expect(waiting.checks == "PENDING")

        // A required failure is a failure; nothing known counts all.
        let red = try #require(await GitHubClient.summaries(fromJSON: json) { _ in ["nightly"] }.first)
        #expect(red.checks == "FAILURE")
        #expect(red.failingCheckLinks == ["https://ci/nightly"])
        #expect(red.optionalFailures == 0)
        let unknown = try #require(await GitHubClient.summaries(fromJSON: json) { _ in [] }.first)
        #expect(unknown.checks == "FAILURE")
        #expect(await GitHubClient.summaries(fromJSON: json) { _ in [] }.first?.checks == "FAILURE")

        // A status context errs rather than fails; it is a failure
        // all the same, to open and to count.
        let erred = json.replacing(#""state": "SUCCESS"}"#, with: #""state": "ERROR", "targetUrl": "https://ci/lint"}"#)
        let context = try #require(await GitHubClient.summaries(fromJSON: erred) { _ in ["nightly"] }.first)
        #expect(context.checks == "FAILURE")
        #expect(context.optionalFailures == 1)

        // A full query answering no checks at all for a branch that
        // requires some is waiting on them, not clear; only a light
        // listing, which never asked, says nothing.
        let none = """
        [{"number": 10, "title": "Fix", "url": "https://github.com/o/r/pull/10", "headRefName": "c",
          "baseRefName": "main", "mergeable": "", "reviewDecision": ""}]
        """
        let waited = try #require(await GitHubClient.summaries(fromJSON: none) { _ in ["build"] }.first)
        #expect(waited.checks == "PENDING")
        let required: GitHubClient.RequiredChecksReader = { _ in ["build"] }
        let light = await GitHubClient.summaries(fromJSON: none, requiredChecks: required, askedForChecks: false)
        #expect(light.first?.checks.isEmpty == true)
    }

    @Test
    func `a branch's rules name its required checks and whether it takes a push`() {
        let branch = #"{"protected": true, "required": ["build"]}"#
        let rules = """
        [{"type": "pull_request", "parameters": {}},
         {"type": "required_status_checks", "parameters": {"strict_required_status_checks_policy": false,
          "required_status_checks": [{"context": "lint", "integration_id": 15368}, {"context": "build"}]}}]
        """
        let guarded = GitHubClient.branchRules(branchJSON: branch, rulesJSON: rules)
        #expect(guarded.requiredChecks == ["build", "lint"])
        #expect(guarded.isProtected)
        #expect(guarded.takesPushes == false)

        let open = GitHubClient.branchRules(branchJSON: #"{"protected": false, "required": []}"#, rulesJSON: "[]")
        #expect(open.requiredChecks.isEmpty)
        #expect(open.takesPushes)
        // A rule that is not about checks still refuses the push.
        let reviewed = GitHubClient.branchRules(branchJSON: "{}", rulesJSON: #"[{"type": "pull_request"}]"#)
        #expect(reviewed.takesPushes == false)
        #expect(reviewed.requiredChecks.isEmpty)
    }
}
