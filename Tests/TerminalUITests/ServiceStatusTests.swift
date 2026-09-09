import Foundation
@testable import TerminalUI
import Testing

/// A read that failed once is not news until it fails again: the
/// next poll is the recovery every read has.
@MainActor
struct ServiceStatusTests {
    // MARK: Internal

    @Test
    func `a read failure is reported only when it repeats`() {
        let status = ServiceStatus.shared
        let what = "Reading " + UUID().uuidString

        status.record(failure: Failure(errorDescription: "first"), doing: what)
        #expect(reported(what) == nil)

        // A success in between makes the first not news.
        status.recordSuccess(doing: what)
        status.record(failure: Failure(errorDescription: "second"), doing: what)
        #expect(reported(what) == nil)

        status.record(failure: Failure(errorDescription: "third"), doing: what)
        let message = reported(what) ?? ""
        #expect(message.contains("second"))
        #expect(message.contains("third"))
        #expect(message.contains("first") == false)
    }

    @Test
    func `a held failure nobody reads again is reported anyway`() async throws {
        let what = "Reading " + UUID().uuidString
        ServiceStatus.shared.record(
            failure: Failure(errorDescription: "once"),
            doing: what,
            holdingFor: .milliseconds(50),
        )
        #expect(reported(what) == nil)

        // The deadline is a task on a loaded test run; give it a
        // moment, then a few more.
        for _ in 0 ..< Self.readAttempts where reported(what) == nil {
            try await Task.sleep(for: .milliseconds(Self.readWaitMilliseconds))
        }
        #expect(reported(what)?.contains("not read again") == true)
    }

    // MARK: Private

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let readAttempts = 40
    private static let readWaitMilliseconds = 100

    /// The log's message about one read, if any; other suites write
    /// to the same log beside this one.
    private func reported(_ what: String) -> String? {
        ErrorLog.shared.entries.last { $0.message.contains(what) }?.message
    }
}
