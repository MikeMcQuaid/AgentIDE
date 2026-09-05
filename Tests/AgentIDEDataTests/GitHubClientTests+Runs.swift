@testable import AgentIDEData
import Testing

// MARK: - Run logs

/// Reading an Actions run's failing logs: which jobs count as
/// failed, where each log comes from while the run is still going,
/// and what is said when none of them can be read yet. Split from
/// the client's tests for length.
extension GitHubClientTests {
    @Test
    func `failed jobs parse from a run's jobs listing`() {
        let json = """
        {"jobs": [
          {"databaseId": 11, "name": "style", "conclusion": "failure"},
          {"databaseId": 12, "name": "test", "conclusion": null},
          {"databaseId": 13, "name": "build", "conclusion": "success"}
        ]}
        """
        #expect(GitHubClient.failedJobs(fromJSON: json).map(\.databaseId) == [11]) // swiftformat:disable:this acronyms
        #expect(GitHubClient.failedJobs(fromJSON: json).map(\.name) == ["style"])
        #expect(GitHubClient.failedJobs(fromJSON: "").isEmpty)
    }

    @Test
    func `failing logs fall back to failed jobs while a run runs`() async throws {
        let jobs = #"{"jobs": [{"databaseId": 11, "conclusion": "failure"}, {"databaseId": 12, "conclusion": null}]}"#
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(jobs),
            "gh run view --job 11 --log-failed": .success("job\tstep\tline\n"),
        ])
        let log = try await GitHubClient(runner: runner).failedRunLog(repositoryPath: "/repo", runID: 9)
        #expect(log == "job\tstep\tline")
    }

    @Test
    func `a job gh still refuses answers from the plain job log`() async throws {
        // gh refuses even a completed job's view while its run is in
        // progress; the REST log has no such gate.
        let jobs = #"{"jobs": [{"databaseId": 11, "name": "style", "conclusion": "failure"}]}"#
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(jobs),
            "gh run view --job 11 --log-failed": .failure("run 9 is still in progress"),
            "gh api repos/{owner}/{repo}/actions/jobs/11/logs": .success("2026-09-01T10:00:00Z it broke\n"),
        ])
        let log = try await GitHubClient(runner: runner).failedRunLog(repositoryPath: "/repo", runID: 9)
        #expect(log == "[job style]\n2026-09-01T10:00:00Z it broke")
    }

    @Test
    func `a job with no log yet is skipped rather than fatal`() async throws {
        let jobs = #"""
        {"jobs": [{"databaseId": 11, "name": "early", "conclusion": "failure"},
                  {"databaseId": 12, "name": "late", "conclusion": "failure"}]}
        """#
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(jobs),
            "gh run view --job 11 --log-failed": .success("early\tstep\tbroke here\n"),
            "gh run view --job 12 --log-failed": .failure("run 9 is still in progress"),
            "gh api repos/{owner}/{repo}/actions/jobs/12/logs": .failure("still uploading"),
        ])
        let log = try await GitHubClient(runner: runner).failedRunLog(repositoryPath: "/repo", runID: 9)
        #expect(log == "early\tstep\tbroke here")
    }

    @Test
    func `an answer that is not log text is dropped rather than pasted`() async {
        #expect(GitHubClient.isText("2026-09-01T10:00:00Z it broke"))
        #expect(GitHubClient.isText("") == false)
        #expect(GitHubClient.isText("PK\u{3}\u{4}rubbish") == false)
        #expect(GitHubClient.isText("some\0bytes") == false)

        // A job whose log comes back as anything but text leaves the
        // run's own refusal standing, rather than a prompt full of
        // an archive's innards.
        let jobs = #"{"jobs": [{"databaseId": 11, "name": "style", "conclusion": "failure"}]}"#
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(jobs),
            "gh run view --job 11 --log-failed": .failure("run 9 is still in progress"),
            "gh api repos/{owner}/{repo}/actions/jobs/11/logs": .success("PK\u{3}\u{4}archive"),
        ])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner).failedRunLog(repositoryPath: "/repo", runID: 9)
        }
    }

    @Test
    func `a job whose step failed counts, though it is still running`() {
        // The check goes red the moment a step fails; the job's own
        // conclusion stays null until it finishes, and waiting for
        // that is what left nothing to copy.
        let json = """
        {"jobs": [
          {"databaseId": 11, "name": "style", "conclusion": null,
           "steps": [{"conclusion": "success"}, {"conclusion": "failure"}]},
          {"databaseId": 12, "name": "test", "conclusion": null,
           "steps": [{"conclusion": "success"}]},
          {"databaseId": 13, "name": "build", "conclusion": "cancelled", "steps": []}
        ]}
        """
        #expect(GitHubClient.failedJobs(fromJSON: json).map(\.name) == ["style", "build"])
    }

    @Test
    func `nothing readable yet says so in the app's own words`() async throws {
        let jobs = #"""
        {"url": "https://github.com/o/r/actions/runs/9",
         "jobs": [{"databaseId": 11, "name": "style", "conclusion": "failure"}]}
        """#
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(jobs),
            "gh run view --job 11 --log-failed": .failure("run 9 is still in progress"),
            "gh api repos/{owner}/{repo}/actions/jobs/11/logs": .failure("still uploading"),
        ])
        let failure = await #expect(throws: GitHubClient.RunLogsUnavailable.self) {
            try await GitHubClient(runner: runner) { true }
                .failedRunLog(repositoryPath: "/repo", runID: 9)
        }
        // gh's own wording never reaches the messages pane, and
        // neither does a claim that GitHub has no logs: it has
        // them, and shows them live where the message points.
        let message = try #require(failure?.localizedDescription)
        #expect(message.contains("still in progress") == false)
        #expect(message.contains("no logs") == false)
        #expect(message.contains("only once the job has finished"))
        #expect(message.contains("https://github.com/o/r/actions/runs/9/job/11"))
    }

    @Test
    func `a run in progress with no failed job keeps its own error`() async {
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --log-failed": .failure("run 9 is still in progress"),
            "gh run view 9 --json url,jobs": .success(#"{"jobs": [{"databaseId": 12, "conclusion": null}]}"#),
        ])
        await #expect(throws: Error.self) {
            try await GitHubClient(runner: runner).failedRunLog(repositoryPath: "/repo", runID: 9)
        }
    }
}

// MARK: - ScriptedGitHubRunner

/// Answers each expected command from a script; anything unexpected
/// fails, naming itself.
private final class ScriptedGitHubRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(answers: [String: Answer]) {
        self.answers = answers
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    enum Answer {
        case success(String)
        case failure(String)
    }

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) -> ProcessResult {
        let command = arguments.joined(separator: " ")
        return switch answers[command] {
        case let .success(output):
            ProcessResult(status: 0, standardOutput: output, standardError: "")

        case let .failure(message):
            ProcessResult(status: 1, standardOutput: "", standardError: message)

        case nil:
            ProcessResult(status: 1, standardOutput: "", standardError: "unscripted command: " + command)
        }
    }

    // MARK: Private

    private let answers: [String: Answer]
}
