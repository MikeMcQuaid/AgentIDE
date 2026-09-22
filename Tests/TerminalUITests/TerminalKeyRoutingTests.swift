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
        let pane = try Self.focusedPane(herdrBacked: herdrBacked)
        defer { pane.window.close() }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: pane.window.windowNumber,
            context: nil,
            characters: keyCode == 126 ? "\u{F700}" : "\u{F701}",
            charactersIgnoringModifiers: keyCode == 126 ? "\u{F700}" : "\u{F701}",
            isARepeat: false,
            keyCode: keyCode,
        ))

        if let forwarded = pane.view.routeKey(event) {
            pane.view.keyDown(with: forwarded)
        }

        #expect(String(bytes: pane.capture.bytes, encoding: .utf8)
            == (herdrBacked ? "\u{1B}[1;3" : "\u{1B}\u{1B}[") + (keyCode == 126 ? "A" : "B"))
    }

    /// The keypad digits, the separator and the operators, against a
    /// shell that has asked for application keypad mode the way zsh
    /// does at every prompt.
    @Test(arguments: [("5", UInt16(87)), (".", 65), ("+", 69), ("/", 75)])
    func `keypad keys type their own characters in application keypad mode`(
        character: String,
        keyCode: UInt16,
    ) throws {
        let pane = try Self.focusedPane(herdrBacked: false)
        defer { pane.window.close() }
        pane.view.feed(text: "\u{1B}=")
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .numericPad,
            timestamp: 0,
            windowNumber: pane.window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode,
        ))

        if let forwarded = pane.view.routeKey(event) {
            pane.view.keyDown(with: forwarded)
        }

        #expect(String(bytes: pane.capture.bytes, encoding: .utf8) == character)
    }

    // MARK: Private

    /// A pane, its window and the bytes it sends.
    private struct Pane {
        let view: PaneTerminalView
        let window: NSWindow
        let capture: InputCapture
    }

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

    /// A pane in a key window, with its input captured and no
    /// keyboard enhancements in play.
    private static func focusedPane(herdrBacked: Bool) throws -> Pane {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isHerdrBacked = herdrBacked
        let capture = InputCapture()
        view.terminalDelegate = capture
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        try #require(window.makeFirstResponder(view))
        #expect(view.getTerminal().keyboardEnhancementFlags.isEmpty)
        return Pane(view: view, window: window, capture: capture)
    }
}
