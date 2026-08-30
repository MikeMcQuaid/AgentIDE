import Foundation
@testable import PRFeature
import Testing

/// The failing logs: Actions runs found in the check links, each
/// log cut to its tail, condensed to what a fix prompt needs.
extension PullRequestsModelTests {
    @Test
    func `failing logs gather each run's tail once`() async throws {
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
        #expect(text.hasPrefix("## Run 123\n[100 earlier lines cut]\nline 101\n"))
        #expect(text.hasSuffix("\n\n## Run 456\nshort"))
        #expect(text.contains("line 100\n") == false)
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
