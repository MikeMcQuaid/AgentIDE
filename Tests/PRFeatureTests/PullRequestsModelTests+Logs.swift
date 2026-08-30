import Foundation
@testable import PRFeature
import Testing

/// The failing logs: Actions runs found in the check links, each
/// log cut to its tail under a heading.
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
}
