import AppKit
import SwiftTerm
@testable import TerminalUI
import Testing

@MainActor
struct TerminalKeyRoutingTests {
    // MARK: Internal

    @Test(arguments: [false, true], [UInt16(126), 125])
    func `agent option arrows keep their modifiers without local keyboard modes`(
        herdrBacked: Bool,
        keyCode: UInt16,
    ) throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isHerdrBacked = herdrBacked
        let capture = InputCapture()
        view.terminalDelegate = capture
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        try #require(window.makeFirstResponder(view))
        #expect(view.getTerminal().keyboardEnhancementFlags.isEmpty)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: keyCode == 126 ? "\u{F700}" : "\u{F701}",
            charactersIgnoringModifiers: keyCode == 126 ? "\u{F700}" : "\u{F701}",
            isARepeat: false,
            keyCode: keyCode,
        ))

        if let forwarded = view.routeKey(event) {
            view.keyDown(with: forwarded)
        }

        #expect(String(bytes: capture.bytes, encoding: .utf8)
            == (herdrBacked ? "\u{1B}[1;3" : "\u{1B}\u{1B}[") + (keyCode == 126 ? "A" : "B"))
    }

    // MARK: Private

    private final class InputCapture: TerminalViewDelegate {
        // MARK: Lifecycle

        deinit {
            // No resources beyond the captured bytes.
        }

        // MARK: Internal

        var bytes: [UInt8] = []

        func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            bytes.append(contentsOf: data)
        }

        func sizeChanged(source _: TerminalView, newCols _: Int, newRows _: Int) {
            // Only input is captured.
        }

        func setTerminalTitle(source _: TerminalView, title _: String) {
            // Only input is captured.
        }

        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
            // Only input is captured.
        }

        func scrolled(source _: TerminalView, position _: Double) {
            // Only input is captured.
        }

        func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {
            // Only input is captured.
        }
    }
}
