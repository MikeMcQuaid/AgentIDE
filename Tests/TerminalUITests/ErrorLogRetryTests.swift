import Foundation
@testable import TerminalUI
import Testing

/// Work that can simply be tried again is, once, before its failure
/// is reported.
@MainActor
struct ErrorLogRetryTests {
    // MARK: Internal

    @Test
    func `a second try that succeeds reports nothing`() async {
        let what = "Trying " + UUID().uuidString
        var tries = 0
        let succeeded = await ErrorLog.shared.attemptingTwice(what) {
            tries += 1
            if tries == 1 {
                throw Failure(errorDescription: "first")
            }
        }
        #expect(succeeded)
        #expect(tries == 2)
        #expect(ErrorLog.shared.entries.contains { $0.message.contains(what) } == false)
    }

    @Test
    func `two failures report once, naming both`() async {
        let what = "Trying " + UUID().uuidString
        var tries = 0
        let succeeded = await ErrorLog.shared.attemptingTwice(what) {
            tries += 1
            throw Failure(errorDescription: "try " + String(tries))
        }
        #expect(succeeded == false)
        #expect(tries == 2)
        let about = ErrorLog.shared.entries.filter { $0.message.contains(what) }
        #expect(about.count == 1)
        #expect(about.first?.message.contains("try 1") == true)
        #expect(about.first?.message.contains("try 2") == true)
    }

    // MARK: Private

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }
}
