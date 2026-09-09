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
        let before = ErrorLog.shared.entries.count

        status.record(failure: Failure(errorDescription: "first"), doing: what)
        #expect(ErrorLog.shared.entries.count == before)

        // A success in between makes the first not news.
        status.recordSuccess(doing: what)
        status.record(failure: Failure(errorDescription: "second"), doing: what)
        #expect(ErrorLog.shared.entries.count == before)

        status.record(failure: Failure(errorDescription: "third"), doing: what)
        #expect(ErrorLog.shared.entries.count == before + 1)
        let reported = ErrorLog.shared.entries.last?.message ?? ""
        #expect(reported.contains(what))
        #expect(reported.contains("second"))
        #expect(reported.contains("third"))
        #expect(reported.contains("first") == false)
    }

    // MARK: Private

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }
}
