import AppKit
@testable import TerminalUI
import Testing

/// Drive native selection through the same public events as a real drag.
@MainActor
enum TerminalMouse {
    // MARK: Internal

    static func select(
        in view: PaneTerminalView,
        row: Int,
        from start: Double,
        to end: Double,
        endRow: Int? = nil,
        modifiers: NSEvent.ModifierFlags = [],
    ) throws {
        let cell = PaneTerminalView.cellSize(of: view)
        for (type, column, eventRow) in [
            (NSEvent.EventType.leftMouseDown, start, row),
            (.leftMouseDragged, end, endRow ?? row),
            (.leftMouseUp, end, endRow ?? row),
        ] {
            let point = NSPoint(
                x: column * cell.width,
                y: view.bounds.height - (CGFloat(eventRow) + Self.cellCentre) * cell.height,
            )
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: view.convert(point, to: nil),
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: unsafe view.window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1,
            ))
            switch type {
            case .leftMouseDown:
                view.mouseDown(with: event)

            case .leftMouseDragged:
                view.mouseDragged(with: event)

            default:
                view.mouseUp(with: event)
            }
        }
    }

    // MARK: Private

    private static let cellCentre = 0.5
}
