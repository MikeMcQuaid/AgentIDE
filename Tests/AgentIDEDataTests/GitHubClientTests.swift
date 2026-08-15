@testable import AgentIDEData
import AgentIDEDomain
import Testing

/// Exercises the pure parsing and prompt composition around `gh`.
struct GitHubClientTests {
    @Test
    func `rest comments group into anchored threads by reply chains`() {
        let json = """
        [
          {"id": 1, "path": "a.swift", "line": 4, "body": "First",
           "user": {"login": "copilot"}},
          {"id": 2, "path": "a.swift", "line": 4, "in_reply_to_id": 1,
           "body": "Reply", "user": {"login": "mike"}},
          {"id": 3, "path": "b.swift", "original_line": 9,
           "body": "Other", "user": {"login": "copilot"}}
        ]
        """
        let threads = GitHubClient.threads(fromRESTJSON: json)
        #expect(threads.count == 2)
        #expect(threads.first?.path == "a.swift")
        #expect(threads.first?.line == 4)
        #expect(threads.first?.comments.map(\.author) == ["copilot", "mike"])
        #expect(threads.last?.line == 9)
        // REST threads carry no resolvable id.
        #expect(threads.map(\.id) == ["", ""])
    }

    @Test
    func `run ids come deduplicated from failing check links`() {
        let lines = [
            "build\tfail\t1m2s\thttps://github.com/o/r/actions/runs/123/job/456",
            "test\tfail\t2m\thttps://github.com/o/r/actions/runs/123/job/789",
            "style\tfail\t3s\thttps://github.com/o/r/actions/runs/987/job/1",
            "external-ci\tfail\t5s\thttps://ci.example.invalid/build/9",
        ]
        #expect(GitHubClient.runIDs(fromCheckLines: lines) == ["123", "987"])
        #expect(GitHubClient.runIDs(fromCheckLines: []).isEmpty)
    }

    @Test
    func `merge flags follow the repository's allowed methods`() {
        // A merge commit wins whenever it is allowed.
        let all = #"{"mergeCommitAllowed":true,"rebaseMergeAllowed":true,"squashMergeAllowed":true}"#
        #expect(GitHubClient.mergeFlag(fromJSON: all) == "--merge")
        let noMergeCommit = #"{"mergeCommitAllowed":false,"rebaseMergeAllowed":true,"squashMergeAllowed":true}"#
        #expect(GitHubClient.mergeFlag(fromJSON: noMergeCommit) == "--rebase")
        let squashOnly = #"{"mergeCommitAllowed":false,"rebaseMergeAllowed":false,"squashMergeAllowed":true}"#
        #expect(GitHubClient.mergeFlag(fromJSON: squashOnly) == "--squash")
        // An unreadable answer defaults to the merge commit.
        #expect(GitHubClient.mergeFlag(fromJSON: "") == "--merge")
    }

    @Test
    func `summaries carry failing check links and click through sensibly`() throws {
        let json = """
        [{"number": 7, "title": "Fix", "url": "https://github.com/o/r/pull/7",
          "headRefName": "agent/fix", "mergeable": "MERGEABLE", "reviewDecision": "",
          "statusCheckRollup": [
            {"state": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://ci/ok"},
            {"state": "COMPLETED", "conclusion": "FAILURE", "detailsUrl": "https://ci/broken"}
          ]}]
        """
        let summary = try #require(GitHubClient.summaries(fromJSON: json).first)
        #expect(summary.checks == "FAILURE")
        #expect(summary.failingCheckLinks == ["https://ci/broken"])
        #expect(summary.checksClickURL == "https://ci/broken")
        #expect(summary.checksPageURL == "https://github.com/o/r/pull/7/checks")
    }

    @Test
    func `many failing checks click through to the checks page`() throws {
        let json = """
        [{"number": 8, "title": "Fix", "url": "https://github.com/o/r/pull/8",
          "headRefName": "b", "mergeable": "", "reviewDecision": "",
          "statusCheckRollup": [
            {"state": "COMPLETED", "conclusion": "FAILURE", "detailsUrl": "https://ci/one"},
            {"state": "COMPLETED", "conclusion": "FAILURE", "detailsUrl": "https://ci/two"}
          ]}]
        """
        let summary = try #require(GitHubClient.summaries(fromJSON: json).first)
        #expect(summary.checksClickURL == "https://github.com/o/r/pull/8/checks")
    }

    @Test
    func `issue and pull request prompts compose title, body and context`() {
        let issue = GitHubClient.issuePrompt(number: 3, title: "Crash", body: "Steps", context: "Be careful")
        #expect(issue.contains("issue #3: Crash"))
        #expect(issue.contains("Steps"))
        #expect(issue.contains("Be careful"))
        #expect(issue.contains("Do not push."))

        let pullRequest = GitHubClient.pullRequestPrompt(number: 4, title: "Fix", body: "", context: "")
        #expect(pullRequest.contains("pull request #4: Fix"))
        #expect(pullRequest.contains("checked out here"))
    }

    @Test
    func `list scopes build the right gh invocations`() {
        let branch = GitHubClient.listArguments(scope: .branch("agent/fix"))
        #expect(branch.contains("--head"))
        #expect(branch.contains("agent/fix"))
        #expect(branch.contains("all"))

        let mine = GitHubClient.listArguments(scope: .mine)
        #expect(mine.contains("--author"))
        #expect(mine.contains("@me"))

        let open = GitHubClient.listArguments(scope: .open)
        #expect(open.contains("--author") == false)
        #expect(open.contains("--head") == false)
    }

    @Test
    func `summaries carry base branch and state`() throws {
        let json = """
        [{"number": 9, "title": "T", "url": "https://github.com/o/r/pull/9",
          "headRefName": "b", "baseRefName": "main", "state": "MERGED",
          "mergeable": "", "reviewDecision": ""}]
        """
        let summary = try #require(GitHubClient.summaries(fromJSON: json).first)
        #expect(summary.baseBranch == "main")
        #expect(summary.state == "MERGED")
    }

    @Test
    func `runners build model and effort arguments`() {
        let claude = ClaudeCodeRunner()
        #expect(claude.optionArguments(model: "fable", effort: "max") == "--model fable --effort max")
        #expect(claude.optionArguments(model: nil, effort: nil).isEmpty)
        #expect(claude.models.contains("fable"))

        let codex = CodexRunner()
        #expect(codex.optionArguments(model: "sol", effort: "high")
            == "--model sol -c model_reasoning_effort=high")
        #expect(codex.models.contains("gpt-5.6-sol"))
        #expect(codex.models.contains("gpt-5.4"))
    }

    @Test
    func `model listings parse through colour codes and bullets`() {
        let output = """
        \u{1B}[1mAvailable models\u{1B}[0m
        - gpt-5.6-sol  (default)
        * gpt-5.6-terra
          gpt-5.6-luna
        gpt-5.5
        Run codex --model <name> to pick one.
        """
        let models = CodexRunner().parseModelList(output)
        #expect(models.contains("gpt-5.6-sol"))
        #expect(models.contains("gpt-5.6-terra"))
        #expect(models.contains("gpt-5.6-luna"))
        #expect(models.contains("gpt-5.5"))
        #expect(models.contains("Available") == false)
    }
}
