import AgentIDEDomain
import AppKit
import SwiftTerm

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour.
final class PaneTerminalView: LocalProcessTerminalView {
    // MARK: Lifecycle

    deinit {
        // The PTY dies with the view.
    }

    // MARK: Internal

    /// Reflows multi-line copies for pasting into prose tools.
    var reflowsCopies = false

    /// Native selection copy, reflowed for prose panes.
    override func copy(_ sender: Any) {
        super.copy(sender)
        guard reflowsCopies,
              let text = NSPasteboard.general.string(forType: .string),
              text.contains("\n")
        else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(PasteableText.reflow(text), forType: .string)
    }
}

// MARK: - BlockSelector

/// Option-drag rectangular selection: a marquee over the terminal
/// whose release copies the column slice of every touched row, with
/// gutter marks and trailing spaces trimmed. Fed by an event
/// monitor, since SwiftTerm's mouse handling is not overridable.
@MainActor
final class BlockSelector {
    // MARK: Lifecycle

    /// Creates a selector over one terminal view.
    init(view: PaneTerminalView) {
        self.view = view
    }

    deinit {
        // The overlay is removed with the view.
    }

    // MARK: Internal

    /// Routes one mouse event; nil means it was consumed.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard let view else {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            let point = view.convert(event.locationInWindow, from: nil)
            guard event.modifierFlags.contains(.option), view.bounds.contains(point) else {
                return event
            }

            begin(at: point, in: view)
            return nil

        case .leftMouseDragged where anchor != nil:
            update(to: view.convert(event.locationInWindow, from: nil), in: view)
            return nil

        case .leftMouseUp where anchor != nil:
            finish(at: view.convert(event.locationInWindow, from: nil), in: view)
            return nil

        default:
            return event
        }
    }

    // MARK: Private

    private static let marqueeOpacity = 0.2

    private weak var view: PaneTerminalView?
    private var anchor: CGPoint?
    private var overlay: NSView?

    private func begin(at point: CGPoint, in view: PaneTerminalView) {
        anchor = point
        let marquee = NSView(frame: CGRect(origin: point, size: .zero))
        marquee.wantsLayer = true
        marquee.layer?.borderWidth = 1
        marquee.layer?.borderColor = NSColor.controlAccentColor.cgColor
        marquee.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(Self.marqueeOpacity)
            .cgColor
        view.addSubview(marquee)
        overlay = marquee
    }

    private func update(to point: CGPoint, in view: PaneTerminalView) {
        guard let anchor else {
            return
        }

        let clamped = CGPoint(
            x: min(max(point.x, 0), view.bounds.width),
            y: min(max(point.y, 0), view.bounds.height),
        )
        overlay?.frame = CGRect(
            x: min(anchor.x, clamped.x),
            y: min(anchor.y, clamped.y),
            width: abs(clamped.x - anchor.x),
            height: abs(clamped.y - anchor.y),
        )
    }

    private func finish(at point: CGPoint, in view: PaneTerminalView) {
        defer {
            overlay?.removeFromSuperview()
            overlay = nil
            anchor = nil
        }
        guard let anchor else {
            return
        }

        copyRectangle(from: anchor, to: point, in: view)
    }

    /// Copies the rectangle's rows, each sliced to its columns.
    private func copyRectangle(from start: CGPoint, to end: CGPoint, in view: PaneTerminalView) {
        let terminal = view.getTerminal()
        guard terminal.rows > 0, terminal.cols > 0 else {
            return
        }

        let rowHeight = view.frame.height / CGFloat(terminal.rows)
        let colWidth = view.frame.width / CGFloat(terminal.cols)
        func gridRow(_ vertical: CGFloat) -> Int {
            // The view's origin is at the bottom; rows count from
            // the top.
            min(max(Int((view.frame.height - vertical) / rowHeight), 0), terminal.rows - 1)
        }
        func gridCol(_ horizontal: CGFloat) -> Int {
            min(max(Int(horizontal / colWidth), 0), terminal.cols - 1)
        }
        let top = min(gridRow(start.y), gridRow(end.y))
        let bottom = max(gridRow(start.y), gridRow(end.y))
        let left = min(gridCol(start.x), gridCol(end.x))
        let right = max(gridCol(start.x), gridCol(end.x))

        var lines = [String]()
        for row in top ... bottom {
            guard let line = terminal.getLine(row: row) else {
                continue
            }

            let text = line.translateToString(trimRight: true, startCol: left, endCol: right + 1)
            lines.append(PasteableText.strippingGutter(text))
        }
        let joined = lines.joined(separator: "\n")
        guard joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(joined, forType: .string)
    }
}
