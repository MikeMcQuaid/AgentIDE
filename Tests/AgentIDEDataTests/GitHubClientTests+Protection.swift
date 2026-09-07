@testable import AgentIDEData
import Testing

// MARK: - RulesFailingRunner

/// A `gh` whose branch read says unprotected and whose rules read
/// fails, the shape of an outage or an endpoint a plan lacks.
private struct RulesFailingRunner: ProcessRunner {
    func run(_ arguments: [String], workingDirectory _: String?, environment _: [String: String]) -> ProcessResult {
        if arguments.first == "git" || arguments.contains("remote") {
            return ProcessResult(status: 0, standardOutput: "git@github.com:mike/repo.git\n", standardError: "")
        }
        if arguments.contains(where: { $0.hasPrefix("repos/{owner}/{repo}/rules/") }) {
            return ProcessResult(status: 1, standardOutput: "", standardError: "gh: Not Found (HTTP 404)")
        }

        return ProcessResult(status: 0, standardOutput: "false\n", standardError: "")
    }
}

// MARK: - GitHubClientTests

/// Whether a default branch takes a push, from what GitHub says of it.
extension GitHubClientTests {
    @Test
    func `a rules read that fails is no answer, not an empty rule list`() async {
        // Read as no rules the branch would have taken pushes, which
        // is the one answer a failed read must never give.
        let policy = await GitHubClient(runner: RulesFailingRunner())
            .pushPolicy(repositoryPath: "/repo", branch: "main")
        #expect(policy == .unknown)
    }

    @Test
    func `protection and pull request rules refuse a push, nothing else does`() {
        // A repository of your own: unprotected, no rules.
        #expect(GitHubClient.acceptsPushes(protectedFlag: "false\n", rulesJSON: "[]"))
        // Classic protection alone refuses.
        #expect(GitHubClient.acceptsPushes(protectedFlag: "true\n", rulesJSON: "[]") == false)
        // A ruleset wanting a pull request, or checks only a pull
        // request runs, refuses; one that only forbids deleting the
        // branch does not.
        let wantsPullRequest = #"[{"type": "deletion"}, {"type": "pull_request", "parameters": {}}]"#
        #expect(GitHubClient.acceptsPushes(protectedFlag: "false", rulesJSON: wantsPullRequest) == false)
        let wantsChecks = #"[{"type": "required_status_checks"}]"#
        #expect(GitHubClient.acceptsPushes(protectedFlag: "false", rulesJSON: wantsChecks) == false)
        #expect(GitHubClient.acceptsPushes(protectedFlag: "false", rulesJSON: #"[{"type": "deletion"}]"#))
        // An answer that is not JSON is no rule at all.
        #expect(GitHubClient.acceptsPushes(protectedFlag: "false", rulesJSON: "nonsense"))
    }
}
