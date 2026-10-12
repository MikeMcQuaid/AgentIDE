import AppKit
@testable import TerminalUI
import Testing

/// Rectangular copies use the visible block for both release and Copy.
@MainActor
struct BlockSelectorTests {
    // MARK: Internal

    @Test(arguments: [3, 80], [true, false])
    func `large code rectangles survive Copy and cursor updates`(rows: Int, reflows: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let view = fixture.view
        view.reflowsCopies = reflows
        let lines = (0 ..< rows).map { "print(\"line \($0): café \(String(repeating: "x", count: 80))\")" }
        let expected = lines.joined(separator: "\n")
        view.feed(text: lines.joined(separator: "\r\n"))
        // A stale native selection must not win over the rectangle.
        try TerminalMouse.select(in: view, row: 0, from: 0, to: 5)
        try fixture.select(rows: rows)
        #expect(view.copyPasteboard.string(forType: .string) == expected)
        #expect(fixture.window.firstResponder === view)

        view.feed(text: "\u{1B}[?25l\u{1B}[?25h")
        fixture.selector.follow()
        view.copyPasteboard.clearContents()
        view.copyPasteboard.setString("replaced clipboard", forType: .string)
        view.copy(NSMenuItem())
        #expect(view.copyPasteboard.string(forType: .string) == expected)

        fixture.selector.clear()
        try TerminalMouse.select(in: view, row: 0, from: 0, to: 5)
        view.copy(NSMenuItem())
        #expect(view.copyPasteboard.string(forType: .string) == "print")
    }

    @Test
    func `copy is enabled for a block without a native selection`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.feed(text: "First line\r\nSecond line")
        try fixture.select(rows: 2)
        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        #expect(fixture.view.validateUserInterfaceItem(item))
        fixture.view.reflowsCopies = true
        fixture.view.copy(item)
        #expect(fixture.view.copyPasteboard.string(forType: .string) == "First line\nSecond line")
        fixture.selector.clear()
        #expect(fixture.view.validateUserInterfaceItem(item) == false)
    }

    @Test(arguments: [true, false])
    func `native selection permanently replaces an earlier rectangular copy`(selectAll: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.dropLocalScrollback()
        fixture.view.feed(text: "Block\r\nOutside the block")
        let subviewCount = fixture.view.subviews.count
        try fixture.select(rows: 1)
        #expect(fixture.view.copyPasteboard.string(forType: .string) == "Block")
        if selectAll {
            fixture.view.selectAll(nil)
        } else {
            try TerminalMouse.select(in: fixture.view, row: 1, from: 0, to: 17)
        }
        for _ in 0 ..< 100 where fixture.view.subviews.count != subviewCount {
            await Task.yield()
        }
        #expect(fixture.view.subviews.count == subviewCount)
        let selected = try #require(fixture.view.getSelection())
        #expect(selected.contains("Outside the block"))
        fixture.view.copy(NSMenuItem())
        #expect(fixture.view.copyPasteboard.string(forType: .string) == selected)

        fixture.view.feed(text: "\u{1B}[\(fixture.view.terminalDimensions.rows)S")
        fixture.selector.follow()
        #expect(fixture.view.selectionActive == false)
        #expect(fixture.view.getSelection() == nil)
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        #expect(fixture.view.validateUserInterfaceItem(copy) == false)
        fixture.view.copy(copy)
        #expect(fixture.view.copyPasteboard.string(forType: .string)?.isEmpty == true)
    }

    @Test
    func `a hidden terminal cannot take a rectangular selection`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.feed(text: "hidden output")
        fixture.view.isHidden = true
        fixture.view.copyPasteboard.setString("keep clipboard", forType: .string)
        try fixture.select(rows: 1)
        #expect(fixture.view.copyPasteboard.string(forType: .string) == "keep clipboard")
    }

    @Test(arguments: [
        ("ab界cd", 2 ... 3, "界"),
        ("ab界cd", 4 ... 5, "cd"),
        ("a\u{301}b界cd", 0 ... 1, "a\u{301}b"),
        ("👩‍💻text", 2 ... 5, "text"),
        ("left\u{1B}[8Gright", 2 ... 10, "ft   righ"),
    ])
    func `rectangles slice display cells rather than string offsets`(
        text: String, columns: ClosedRange<Int>, expected: String,
    ) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.view.feed(text: text)
        try fixture.select(rows: 1, columns: columns)
        #expect(fixture.view.copyPasteboard.string(forType: .string) == expected)
    }

    // MARK: Private

    private struct Fixture {
        // MARK: Lifecycle

        init() {
            view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 1_400, height: 1_900))
            view.copyPasteboard = .withUniqueName()
            selector = BlockSelector(view: view)
            window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeFirstResponder(nil)
        }

        // MARK: Internal

        let view: PaneTerminalView
        let selector: BlockSelector
        let window: NSWindow

        func close() {
            view.copyPasteboard.releaseGlobally()
            window.close()
        }

        func select(rows: Int, columns: ClosedRange<Int>? = nil) throws {
            let cell = PaneTerminalView.cellSize(of: view)
            for (type, column, row) in [
                (NSEvent.EventType.leftMouseDown, columns?.lowerBound ?? 0, 0),
                (.leftMouseDragged, columns?.upperBound ?? (view.terminalDimensions.cols - 1), rows - 1),
                (.leftMouseUp, columns?.upperBound ?? (view.terminalDimensions.cols - 1), rows - 1),
            ] {
                let point = NSPoint(
                    x: (CGFloat(column) + 0.5) * cell.width,
                    y: view.frame.height - (CGFloat(row) + 0.5) * cell.height,
                )
                let event = try #require(NSEvent.mouseEvent(
                    with: type,
                    location: view.convert(point, to: nil),
                    modifierFlags: type == .leftMouseDown ? .option : [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1,
                ))
                _ = selector.handle(event)
            }
        }
    }
}
