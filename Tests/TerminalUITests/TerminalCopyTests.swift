import AppKit
@testable import TerminalUI
import Testing

/// Clipboard copies contain readable text rather than terminal cells.
@MainActor
struct TerminalCopyTests {
    @Test(arguments: [false, true])
    func `selection copies clean cursor gaps and padding`(multiline: Bool) throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.feed(text: "\u{1B}[31m▎ Hello\u{1B}[10Gworld\u{1B}[0m")
        if multiline {
            view.feed(text: "\r\n▎ wrapped text")
        }
        try TerminalMouse.select(in: view, row: 0, from: 0, to: 30, endRow: multiline ? 1 : 0)
        view.copy(NSMenuItem())
        #expect(
            view.copyPasteboard.string(forType: .string) == (multiline ? "Hello  world wrapped text" : "Hello  world"),
        )
    }

    @Test
    func `rectangular copies clean hidden characters without reflowing`() {
        let view = PaneTerminalView(frame: .zero)
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.selectedBlockText = "First\u{0}line  \n  Second\u{07}\u{202E} line\u{202C}  "
        view.copy(NSMenuItem())
        #expect(view.copyPasteboard.string(forType: .string) == "First line\n  Second line")
    }

    @Test
    func `copy all output uses the same cleanup`() async throws {
        let view = PaneTerminalView(frame: .zero)
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.onCopyAllOutput = {
            "\u{0}▎ Hello\u{0}world\u{07}\u{2066}  \r\n  wrapped text\u{2069}  "
        }
        view.copyAllOutput(nil)
        let deadline = ContinuousClock.now + .seconds(5)
        while view.copyPasteboard.string(forType: .string) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view.copyPasteboard.string(forType: .string) == "Hello world wrapped text")
    }
}
