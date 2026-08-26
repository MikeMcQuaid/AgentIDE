import AgentIDEDomain
import Foundation
import Testing

/// The performance log is off unless asked for, lives where both
/// users can read it, and keeps a week.
struct PerformanceLogTests {
    @Test
    func `a line older than a week is not kept`() {
        let now = Date()
        #expect(PerformanceLog.keeps(lineWrittenAt: now.addingTimeInterval(-600_000), now: now))
        #expect(PerformanceLog.keeps(lineWrittenAt: now.addingTimeInterval(-700_000), now: now) == false)
    }

    @Test
    func `the gate is the variable or the marker file, never on by itself`() {
        // The environment cannot change under a running process, so
        // the test asserts the rule's shape against whatever this
        // one was launched with.
        let marker = PerformanceLog.file.replacing("performance.log", with: "performance-log")
        let expected = ProcessInfo.processInfo.environment["AGENTIDE_PERFORMANCE_LOG"] != nil
            || FileManager.default.fileExists(atPath: marker)
        #expect(PerformanceLog.isEnabled == expected)
    }

    @Test
    func `the log lives in the shared temporary directory`() {
        #expect(PerformanceLog.file.hasSuffix("/tmp/agentide/performance.log"))
        let overridden = ProcessInfo.processInfo.environment["AGENTIDE_PERFORMANCE_LOG_DIRECTORY"] != nil
        #expect(PerformanceLog.file.hasPrefix("/Users/Shared/sv-") || overridden)
    }
}
