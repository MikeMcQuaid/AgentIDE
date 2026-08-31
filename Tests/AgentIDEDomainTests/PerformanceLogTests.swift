import AgentIDEDomain
import Foundation
import Testing

/// The performance log is off unless asked for, lives where both
/// users can read it, keeps a day and never grows past its cap.
struct PerformanceLogTests {
    @Test
    func `a line older than a day is not kept`() {
        let now = Date()
        #expect(PerformanceLog.keeps(lineWrittenAt: now.addingTimeInterval(-80_000), now: now))
        #expect(PerformanceLog.keeps(lineWrittenAt: now.addingTimeInterval(-90_000), now: now) == false)
    }

    @Test
    func `trimming keeps the newest whole lines that fit`() {
        let text = (1 ... 10).lazy.map { "line-" + String($0) }.joined(separator: "\n") + "\n"

        // Each line is seven bytes and a newline: a budget of
        // twenty-four holds three of them, newest last.
        #expect(PerformanceLog.newest(of: text, within: 24) == "line-8\nline-9\nline-10\n")
        #expect(PerformanceLog.newest(of: text, within: 1).isEmpty)
        #expect(PerformanceLog.newest(of: text, within: 1_000) == text)
        #expect(PerformanceLog.sizeFloor < PerformanceLog.sizeCap)
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
        // script/test points the log into the test scratch; run
        // any other way it is the shared temporary directory.
        if let override = ProcessInfo.processInfo.environment["AGENTIDE_PERFORMANCE_LOG_DIRECTORY"] {
            #expect(PerformanceLog.file == override + "/performance.log")
        } else {
            #expect(PerformanceLog.file.hasSuffix("/tmp/agentide/performance.log"))
            #expect(PerformanceLog.file.hasPrefix("/Users/Shared/sv-"))
        }
    }
}
