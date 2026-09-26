import AgentIDEDomain
import AppKit
@testable import TerminalUI
import Testing

@MainActor
struct TerminalScrollRoutingTests {
    @Test
    func `wheel commands carry the cell under the pointer`() throws {
        let view = PaneTerminalView(frame: NSRect(x: 100, y: 30, width: 400, height: 203))
        view.hideScroller()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        defer { window.close() }
        var commands = [String]()
        view.onScroll = { upwards, lines, column, row in
            commands.append(HerdrTerminal.scrollCommand(upwards: upwards, lines: lines, column: column, row: row))
        }
        let cell = PaneTerminalView.cellSize(of: view)
        let mouse = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: view.convert(NSPoint(x: 7.5 * cell.width, y: view.bounds.height - 4.5 * cell.height), to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0,
        ))
        let wheel = try #require(mouse.cgEvent)
        wheel.type = .scrollWheel
        wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        let event = try #require(NSEvent(cgEvent: wheel))

        #expect(view.routeWheel(event) == nil)
        let command = try #require(commands.first)
        let fields = try #require(JSONSerialization.jsonObject(with: Data(command.utf8)) as? [String: Any])
        #expect(fields["direction"] as? String == "up")
        #expect(fields["lines"] as? Int == 3)
        #expect(fields["column"] as? Int == 7)
        #expect(fields["row"] as? Int == 4)
        _ = view.routeWheel(event)
        #expect(commands.count == 1)
    }
}
