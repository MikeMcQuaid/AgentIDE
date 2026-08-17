@testable import AgentIDEData
import Testing

/// Pins what a failing run's logs paste as: the copy button once
/// produced the head of a long run log, which is setup noise, and
/// carried every line's job and step prefix with it.
struct FailingChecksTests {
    @Test
    func `the excerpt keeps the failure, not the start of the log`() {
        let noise = (1 ... 200).map { "build\ttest\tstep line \($0)" }.joined(separator: "\n")
        let log = noise + "\nbuild\ttest\terror: the thing broke\nbuild\ttest\ttrailing context"
        let excerpt = GitHubClient.failureExcerpt(fromRunLog: log)
        #expect(excerpt.contains("error: the thing broke"))
        #expect(excerpt.contains("trailing context"))
        // The head of the log is what used to fill the clipboard.
        #expect(excerpt.contains("step line 1\n") == false)
        // The repeated job and step prefix names the step once.
        #expect(excerpt.hasPrefix("build / test\n"))
        #expect(excerpt.contains("build\ttest\t") == false)
    }

    @Test
    func `each failed step keeps its own tail`() {
        let log = [
            "build\tcompile\tcompiling",
            "build\tcompile\terror: first failure",
            "build\ttest\trunning",
            "build\ttest\terror: second failure",
        ].joined(separator: "\n")
        let excerpt = GitHubClient.failureExcerpt(fromRunLog: log)
        #expect(excerpt.contains("error: first failure"))
        #expect(excerpt.contains("error: second failure"))
        #expect(excerpt.contains("build / compile"))
        #expect(excerpt.contains("build / test"))
    }
}
