import AppKit
import SanductorDomain
@testable import TerminalUI
import Testing

@MainActor
struct TerminalScrollRoutingTests {
    // MARK: Internal

    @Test(arguments: [false, true])
    func `wheel commands carry the cell under the pointer`(precise: Bool) throws {
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
        let wheel = try wheelEvent(in: view, window: window, cell: cell)
        wheel.type = .scrollWheel
        wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        var event = try #require(NSEvent(cgEvent: wheel))
        if precise {
            wheel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            wheel.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 1)
            wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
            wheel.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1)
            event = try #require(NSEvent(cgEvent: wheel))
            #expect(event.hasPreciseScrollingDeltas)
            #expect(event.scrollingDeltaY > 0 && event.scrollingDeltaY < cell.height)
            for _ in 0 ..< Int((cell.height / event.scrollingDeltaY).rounded(.up)) {
                wheel.timestamp += 1_000_000
                event = try #require(NSEvent(cgEvent: wheel))
                #expect(view.routeWheel(event) == nil)
            }
        } else {
            #expect(view.routeWheel(event) == nil)
        }
        let command = try #require(commands.first)
        let records = command.split(separator: "\n")
        #expect(records.count == (precise ? 1 : 3))
        let record = try #require(records.first)
        let fields = try #require(JSONSerialization.jsonObject(
            with: Data(record.utf8),
        ) as? [String: Any])
        #expect(fields["direction"] as? String == "up")
        #expect(fields["lines"] as? Int == 1)
        #expect(fields["column"] as? Int == 7)
        #expect(fields["row"] as? Int == 4)
        _ = view.routeWheel(event)
        #expect(commands.count == 1)
    }

    // MARK: Private

    private func wheelEvent(in view: PaneTerminalView, window: NSWindow, cell: CGSize) throws -> CGEvent {
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
        return try #require(mouse.cgEvent)
    }
}
