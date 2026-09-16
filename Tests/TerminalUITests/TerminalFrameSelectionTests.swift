import AgentIDEData
import AppKit
@testable import TerminalUI
import Testing

/// Cursor-only frames must leave a copy selection intact.
@MainActor
struct TerminalFrameSelectionTests {
    @Test(arguments: [true, false])
    func `cursor blinks and repaints keep the selected text`(mouseReporting: Bool) {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.allowMouseReporting = mouseReporting
        view.dropLocalScrollback()
        let channel = HerdrTerminalChannel(command: ["true"])
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        coordinator.view = view
        coordinator.channel = channel
        view.feed(text: "selected text\r\nprompt")
        view.selection.startSelection(row: 0, col: 0)
        view.selection.dragExtend(row: 0, col: 13)
        #expect(view.getSelection() == "selected text")

        for frame in [
            "\u{1B}[?25l",
            "\u{1B}[?25h",
            "\u{1B}[?2026h\u{1B}[Hselected text\r\nprompt\u{1B}[?2026l",
        ] {
            coordinator.handle(.frame(bytes: Array(frame.utf8)), from: channel)
            #expect(view.selectionActive)
            #expect(view.getSelection() == "selected text")
            #expect(view.selection.start.row == 0)
            #expect(view.selection.start.col == 0)
            #expect(view.selection.end.row == 0)
            #expect(view.selection.end.col == 13)
            #expect(view.allowMouseReporting == mouseReporting)
        }
    }

    @Test
    func `a selection follows scrolling and clears when its text leaves the screen`() {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.dropLocalScrollback()
        let channel = HerdrTerminalChannel(command: ["true"])
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        coordinator.view = view
        coordinator.channel = channel
        view.feed(text: "\u{1B}[2;1Hselected text")
        view.selection.startSelection(row: 1, col: 0)
        view.selection.dragExtend(row: 1, col: 13)
        #expect(view.getSelection() == "selected text")

        coordinator.handle(.frame(bytes: Array("\u{1B}[S".utf8)), from: channel)
        #expect(view.selectionActive)
        #expect(view.getSelection() == "selected text")
        #expect(view.selection.start.row == 0)
        #expect(view.selection.end.row == 0)
        #expect(view.allowMouseReporting)

        coordinator.handle(.frame(bytes: Array("\u{1B}[S".utf8)), from: channel)
        #expect(view.selectionActive == false)
        #expect(view.getSelection() == nil)
    }
}
