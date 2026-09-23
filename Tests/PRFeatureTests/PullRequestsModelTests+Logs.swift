import AgentIDEData
import Foundation
@testable import PRFeature
import TerminalUI
import Testing

/// The failing logs: Actions runs found in the check links, each
/// log cut to its head and tail, condensed to what a fix prompt
/// needs.
extension PullRequestsModelTests {
    @Test
    func `failing logs gather each run's head and tail once`() async throws {
        let links = [
            "https://github.com/o/r/actions/runs/123/job/1",
            "https://github.com/o/r/actions/runs/123/job/2",
            "https://ci.example.invalid/build/9",
            "https://github.com/o/r/actions/runs/456/job/3",
        ]
        #expect(PullRequestsModel.runIDs(in: links) == [123, 456])

        let model = makeModel()
        let long = (1 ... 300).map { "line " + String($0) }.joined(separator: "\n")
        model.fetchFailedRunLog = { runID in runID == 123 ? long : "short" }
        let text = try await model.failingLogs(for: summary(1, head: "feature", failingCheckLinks: links))
        // The first forty lines, then what was cut, then the last
        // hundred and sixty: the command and its environment at the
        // top, the failure at the bottom, the progress between gone.
        #expect(text.hasPrefix("## Run 123\nline 1\n"))
        #expect(text.contains("\nline 40\n[100 lines cut]\nline 141\n"))
        #expect(text.hasSuffix("\nline 300\n\n## Run 456\nshort"))
        #expect(text.contains("line 100\n") == false)
    }

    @Test
    func `a verdict in the cut middle is kept with the lines around it`() {
        // A run's warnings and its failed test land between the head
        // and the tail: cut with the progress, both ends said only
        // that something failed and never what. Lines 60 and 90 of
        // three hundred sit in the middle the head of forty and the
        // tail of a hundred and sixty leave; line 120 says nothing
        // an error or a failure says, and goes with the rest.
        var lines = (1 ... 300).map { "line " + String($0) }
        lines[59] = "Sources/A.swift:1:1: warning: Unused function 'x()'"
        lines[89] = "✘ Test \"it\" recorded an issue: Expectation failed: delivered"
        lines[119] = "Process completed with exit code 1."
        let text = Self.text(of: lines)
        #expect(text.contains("\nline 40\n[16 lines cut]\nline 57\nline 58\nline 59\nSources/A.swift:1:1: warning"))
        #expect(text.contains("'x()'\nline 61\nline 62\nline 63\n[23 lines cut]\nline 87\nline 88\nline 89\n✘ Test"))
        #expect(text.contains("delivered\nline 91\nline 92\nline 93\n[47 lines cut]\nline 141\n"))
        #expect(text.contains("exit code") == false)
    }

    /// The condensed log as one text.
    private static func text(of lines: [String]) -> String {
        PullRequestsModel.condensed(log: lines.joined(separator: "\n")).flatMap(\.lines).joined(separator: "\n")
    }

    @Test
    func `every error and failure is kept whatever the budget, warnings while it lasts`() {
        // Eight hundred lines of each, longer than the tail's budget
        // together: failures are the point of the copy and all stay;
        // warnings keep the last that fit and count the rest as cut.
        let padding = String(repeating: "x", count: 40)
        var lines = (1 ... 1_000).map { "line " + String($0) }
        for index in 40 ..< 840 {
            lines[index] = "error: " + String(index + 1) + " " + padding
        }
        let errors = Self.text(of: lines)
        #expect(errors.contains("error: 41 ") && errors.contains("error: 840 "))
        #expect(errors.contains(" lines cut]") == false)

        for index in 40 ..< 840 {
            lines[index] = "warning: " + String(index + 1) + " " + padding
        }
        let warnings = Self.text(of: lines)
        #expect(warnings.contains("warning: 840 "))
        #expect(warnings.contains("warning: 41 ") == false)
        #expect(warnings.contains("\nline 40\n[") && warnings.contains(" lines cut]\nwarning: "))
    }

    @Test
    func `an end is bounded in bytes, a giant line cut to fit`() {
        let heading = "job\tstep\t"
        let blob = String(repeating: "x", count: 100_000)
        let lines = (1 ... 300).map { heading + "line " + String($0) }
        // A blob at the tail keeps only its last bytes; a blob at the
        // head keeps only its first; the line count still says what
        // was cut between.
        let tailed = PullRequestsModel.condensed(log: (lines + [heading + blob]).joined(separator: "\n"))
        let last = tailed.last?.lines.last ?? ""
        #expect(last.hasPrefix("\u{2026}"))
        #expect(last.utf8.count <= PullRequestsModel.logTailBytes)
        let headed = PullRequestsModel.condensed(log: ([heading + blob] + lines).joined(separator: "\n"))
        let first = headed.first?.lines.first ?? ""
        #expect(first.hasSuffix("\u{2026}"))
        #expect(first.utf8.count <= PullRequestsModel.logHeadBytes)
        #expect(headed.flatMap(\.lines).contains { $0.hasSuffix(" lines cut]") })
    }

    @Test
    func `a run with nothing readable never sinks the ones that have logs`() async throws {
        let links = [
            "https://github.com/o/r/actions/runs/123/job/1",
            "https://github.com/o/r/actions/runs/456/job/3",
        ]
        let model = makeModel()
        // The first run has nothing to give yet; the second does,
        // and that is what the prompt is for.
        model.fetchFailedRunLog = { runID in
            guard runID == 456 else {
                throw GitHubClient.RunLogsUnavailable(failedJobs: 1)
            }

            return "it broke here"
        }
        let text = try await model.failingLogs(for: summary(1, head: "feature", failingCheckLinks: links))
        #expect(text == "## Run 456\nit broke here")
    }

    @Test
    func `only every run coming back empty is worth saying, in our words`() async {
        let links = ["https://github.com/o/r/actions/runs/123/job/1"]
        let model = makeModel()
        model.fetchFailedRunLog = { _ in throw GitHubClient.RunLogsUnavailable(failedJobs: 2) }

        #expect(await model.copyFailingLogs(summary(1, head: "feature", failingCheckLinks: links)) == false)
        let message = ErrorLog.shared.entries.last?.message ?? ""
        #expect(message.contains("2 failed jobs"))
        // gh's own "still in progress" never reaches the pane.
        #expect(message.contains("still in progress") == false)
        #expect(message.contains("failed:") == false)
    }

    @Test
    func `a failure waiting cannot cure is not reported as a wait`() async {
        let links = ["https://github.com/o/r/actions/runs/123/job/1"]
        let model = makeModel()
        let refusal = NSError(domain: "gh", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "there is no route to the network right now",
        ])
        model.fetchFailedRunLog = { _ in throw refusal }

        #expect(await model.copyFailingLogs(summary(1, head: "feature", failingCheckLinks: links)) == false)
        let message = ErrorLog.shared.entries.last?.message ?? ""
        #expect(message.contains("no route to the network"))
        #expect(message.contains("yet") == false)
    }

    @Test
    func `gh's per-line job, step, timestamp and colour are condensed away`() async throws {
        let stamp = "2026-08-30T12:40:20.1479947Z "
        let log = [
            "tests (ubuntu-latest)\tCheck code styles\t\u{FEFF}" + stamp + "##[group]Run brew install shellcheck",
            "tests (ubuntu-latest)\tCheck code styles\t" + stamp + "\u{1B}[36;1mbrew install shellcheck\u{1B}[0m",
            "tests (ubuntu-latest)\tCheck code styles\t" + stamp + "error: style",
        ].joined(separator: "\n")
        let expected = PullRequestsModel.LogSection(
            heading: "tests (ubuntu-latest) · Check code styles",
            lines: ["##[group]Run brew install shellcheck", "brew install shellcheck", "error: style"],
        )
        #expect(PullRequestsModel.condensed(log: log) == [expected])

        // One job and step fold into the run heading; two get their
        // own headings under it.
        let model = makeModel()
        model.fetchFailedRunLog = { runID in
            runID == 1 ? log : log + "\nbuild\tCompile\t" + stamp + "error: compile"
        }
        let first = summary(1, head: "f", failingCheckLinks: ["https://x/actions/runs/1"])
        let one = try await model.failingLogs(for: first)
        #expect(one.hasPrefix("## Run 1 · tests (ubuntu-latest) · Check code styles\n##[group]Run brew"))
        let second = summary(1, head: "f", failingCheckLinks: ["https://x/actions/runs/2"])
        let two = try await model.failingLogs(for: second)
        #expect(two.contains("## Run 2\n### tests (ubuntu-latest) · Check code styles\n"))
        #expect(two.hasSuffix("\n### build · Compile\nerror: compile"))
    }
}
