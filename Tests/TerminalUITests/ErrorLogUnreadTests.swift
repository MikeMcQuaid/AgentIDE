@testable import TerminalUI
import Testing

@MainActor
struct ErrorLogUnreadTests {
    @Test
    func `reading errors clears the badge without clearing messages`() {
        let log = ErrorLog.shared
        log.clear()
        defer { log.clear() }

        log.note("A status note")
        log.report("First failure")
        log.report("Second failure")
        #expect(log.unreadErrorCount == 2)

        log.markRead()
        #expect(log.unreadErrorCount == 0)
        #expect(log.entries.count == 3)

        log.note("Another status note")
        #expect(log.unreadErrorCount == 0)
        log.report("New failure")
        #expect(log.unreadErrorCount == 1)

        log.markRead()
        log.markRead()
        #expect(log.unreadErrorCount == 0)
        #expect(log.entries.count == 5)
    }

    @Test
    func `clearing and trimming the log preserve unread counts`() {
        let log = ErrorLog.shared
        log.clear()
        defer { log.clear() }

        log.report("Read failure")
        log.markRead()
        for _ in 0 ..< 500 {
            log.note("Status note")
        }
        #expect(log.entries.count == 500)
        #expect(log.unreadErrorCount == 0)

        log.report("Unread failure")
        #expect(log.entries.count == 500)
        #expect(log.unreadErrorCount == 1)
        log.markRead()
        log.clear()
        #expect(log.unreadErrorCount == 0)

        log.report("Failure after clearing")
        #expect(log.unreadErrorCount == 1)
        log.clear()
        #expect(log.unreadErrorCount == 0)
    }
}
