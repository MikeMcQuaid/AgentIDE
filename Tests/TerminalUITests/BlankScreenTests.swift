import AppKit
@testable import TerminalUI
import Testing

/// A blank screen is one with nothing on any visible row.
@MainActor
struct BlankScreenTests {
    @Test
    func `a screen is blank until something is drawn on it`() {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let terminal = view.getTerminal()
        #expect(TerminalRepresentable.Coordinator.isScreenBlank(terminal))
        view.feed(text: "   \r\n")
        #expect(TerminalRepresentable.Coordinator.isScreenBlank(terminal))
        // Spaces written past cells never touched: the untouched
        // cells are NULs, and the row still shows nothing.
        view.feed(text: "\u{1B}[3;20H  ")
        #expect(TerminalRepresentable.Coordinator.isScreenBlank(terminal))
        view.feed(text: "hello")
        #expect(TerminalRepresentable.Coordinator.isScreenBlank(terminal) == false)
    }
}
