import AgentIDEDomain
import AppKit
import SwiftTerm

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
        // The overlay is a subview, removed with the view itself.
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
            guard event.modifierFlags.contains(.option), Self.hitsTerminal(event, in: view) else {
                // Any other click puts the last block selection away,
                // as clicking does to an ordinary one.
                clear()
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

    /// Puts the marquee away, which is what a click elsewhere and a
    /// new drag both mean.
    func clear() {
        overlay?.removeFromSuperview()
        overlay = nil
        anchor = nil
        heldRows = nil
        heldColumns = nil
    }

    /// Moves the held marquee to wherever its text is now, and puts
    /// it away once that text has scrolled out of the buffer
    /// entirely. Called as output arrives.
    func follow() {
        guard let view, let heldRows, let heldColumns, let overlay else {
            return
        }

        let terminal = view.getTerminal()
        let top = terminal.getTopVisibleRow()
        let rows = (heldRows.lowerBound - top) ... (heldRows.upperBound - top)
        guard rows.upperBound >= 0, rows.lowerBound < terminal.rows else {
            clear()
            return
        }

        let visible = max(rows.lowerBound, 0) ... min(rows.upperBound, terminal.rows - 1)
        overlay.frame = rectangle(of: (rows: visible, columns: heldColumns), in: view)
    }

    // MARK: Private

    private static let marqueeOpacity = 0.2

    private weak var view: PaneTerminalView?
    private var anchor: CGPoint?
    private var overlay: NSView?

    /// What the held selection covers, in the buffer's own rows
    /// rather than the screen's: output scrolls the text under a
    /// marquee, and a rectangle that stayed where it was drawn would
    /// end up highlighting whatever arrived next.
    private var heldRows: ClosedRange<Int>?
    private var heldColumns: ClosedRange<Int>?

    /// Whether this terminal is the one under the pointer: it is on
    /// screen, and the click is inside it. Not the window's own hit
    /// test, which was the rule before: panes stay mounted when
    /// another worktree's are showing, faded out rather than
    /// removed, and AppKit still resolves a click to one of those.
    /// The pane the pointer was actually over was told the drag was
    /// not its own, so a shell pane never started a selection while
    /// the covered pane quietly took it.
    private static func hitsTerminal(_ event: NSEvent, in view: PaneTerminalView) -> Bool {
        guard view.window != nil, view.isOnScreen else {
            return false
        }

        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func begin(at point: CGPoint, in view: PaneTerminalView) {
        clear()
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

    /// The cells the drag covers, in the grid's own terms: the
    /// selection is decided here once, so the marquee and the copy
    /// can never disagree about which characters are in it.
    private func cells(
        from start: CGPoint,
        to end: CGPoint,
        in view: PaneTerminalView,
    ) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        let terminal = view.getTerminal()
        guard terminal.rows > 0, terminal.cols > 0, view.frame.width > 0, view.frame.height > 0 else {
            return nil
        }

        let size = cellSize(of: view, rows: terminal.rows, columns: terminal.cols)
        func row(_ vertical: CGFloat) -> Int {
            // The view's origin is at the bottom; rows from the top.
            min(max(Int((view.frame.height - vertical) / size.height), 0), terminal.rows - 1)
        }
        func column(_ horizontal: CGFloat) -> Int {
            min(max(Int(horizontal / size.width), 0), terminal.cols - 1)
        }
        return (
            min(row(start.y), row(end.y)) ... max(row(start.y), row(end.y)),
            min(column(start.x), column(end.x)) ... max(column(start.x), column(end.x)),
        )
    }

    /// Where those cells are on screen, so the marquee covers whole
    /// characters: a rectangle drawn at the pointer cuts characters
    /// in half down its edges, and half a character is neither in
    /// the selection nor out of it as far as the eye can tell.
    private func rectangle(
        of cells: (rows: ClosedRange<Int>, columns: ClosedRange<Int>),
        in view: PaneTerminalView,
    ) -> CGRect {
        let terminal = view.getTerminal()
        let size = cellSize(of: view, rows: terminal.rows, columns: terminal.cols)
        let height = CGFloat(cells.rows.count) * size.height
        return CGRect(
            x: CGFloat(cells.columns.lowerBound) * size.width,
            y: view.frame.height - CGFloat(cells.rows.lowerBound) * size.height - height,
            width: CGFloat(cells.columns.count) * size.width,
            height: height,
        )
    }

    /// One character cell, the size the terminal itself draws it.
    /// Dividing the pane by its rows is not the same thing: the grid
    /// is laid out from the top in whole cells of the font's own
    /// size and whatever is left over sits unused at the bottom, so
    /// a marquee measured against the pane drifted further from the
    /// text with every row down the screen. The optimal frame is
    /// exactly one cell by the grid, the scroller here being hidden.
    private func cellSize(of view: PaneTerminalView, rows: Int, columns: Int) -> CGSize {
        let optimal = view.getOptimalFrameSize().size
        guard optimal.width > 0, optimal.height > 0 else {
            return CGSize(width: view.frame.width / CGFloat(columns), height: view.frame.height / CGFloat(rows))
        }

        // The optimal width includes a shell pane's scroller; the
        // grid stops short of it, and measuring against the full
        // width put every column a cell right and copied blanks.
        let scroller = view.subviews.compactMap { $0 as? NSScroller }.first { $0.isHidden == false }
        let gridWidth = optimal.width - (scroller?.frame.width ?? 0)
        return CGSize(width: gridWidth / CGFloat(columns), height: optimal.height / CGFloat(rows))
    }

    private func update(to point: CGPoint, in view: PaneTerminalView) {
        guard let anchor, let cells = cells(from: anchor, to: point, in: view) else {
            return
        }

        overlay?.frame = rectangle(of: cells, in: view)
    }

    private func finish(at point: CGPoint, in view: PaneTerminalView) {
        // The marquee stays: a selection you can no longer see is one
        // you cannot tell has survived the output arriving under it,
        // and this one survives until it is replaced or clicked away.
        defer { anchor = nil }
        guard let anchor, let cells = cells(from: anchor, to: point, in: view) else {
            clear()
            return
        }

        copy(cells: cells, in: view)
        // Held in the buffer's rows, so it can be followed as the
        // text under it scrolls.
        let top = view.getTerminal().getTopVisibleRow()
        heldRows = (cells.rows.lowerBound + top) ... (cells.rows.upperBound + top)
        heldColumns = cells.columns
    }

    /// Copies the rectangle's rows, each sliced to its columns.
    private func copy(cells: (rows: ClosedRange<Int>, columns: ClosedRange<Int>), in view: PaneTerminalView) {
        let terminal = view.getTerminal()
        var lines = [String]()
        for row in cells.rows {
            guard let line = terminal.getLine(row: row) else {
                continue
            }

            // Cells never written hold NUL; the pasteboard must carry
            // spaces there, as SwiftTerm's own copy does, or a pasted
            // script arrives peppered with ^@ where its indentation
            // and word gaps were.
            let text = line.translateToString(
                trimRight: true,
                startCol: cells.columns.lowerBound,
                endCol: cells.columns.upperBound + 1,
            )
            .replacing("\u{0}", with: " ")
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
