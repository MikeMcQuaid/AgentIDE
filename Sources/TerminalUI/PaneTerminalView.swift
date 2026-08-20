import AgentIDEDomain
import AppKit
import SwiftTerm

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour. Agent
/// panes feed it from a tmux control mode client and never start a
/// process; the shell pane starts a plain local shell on its PTY.
final class PaneTerminalView: LocalProcessTerminalView {
    // MARK: Lifecycle

    deinit {
        // A local shell's PTY dies with the view; control channels
        // are owned by the coordinator.
    }

    // MARK: Internal

    /// Reflows multi-line copies for pasting into prose tools.
    var reflowsCopies = false

    /// Takes a paste whole, before the local terminal turns it into
    /// keystrokes; true means it was delivered, false leaves it to
    /// the terminal's own handling. An agent pane pastes through
    /// tmux, which knows whether the pane's application wants
    /// bracketed paste; a shell pane is its own terminal and
    /// already knows.
    var onPaste: ((String) -> Bool)?

    /// Pastes the clipboard, offering it to the owner first.
    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string),
              onPaste?(text) == true
        else {
            super.paste(sender)
            return
        }
    }

    /// The right-click menu: Copy and Paste, which terminals
    /// otherwise lack entirely.
    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)
        return menu
    }

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
            guard event.modifierFlags.contains(.option), view.bounds.contains(point),
                  view.isHiddenOrHasHiddenAncestor == false,
                  Self.hitsTerminal(event, in: view)
            else {
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

    /// Whether the window resolves the click to this terminal: a
    /// pane kept mounted but covered or hidden must not steal drags
    /// from the view actually under the pointer.
    private static func hitsTerminal(_ event: NSEvent, in view: PaneTerminalView) -> Bool {
        guard let content = view.window?.contentView, let root = content.superview else {
            return false
        }

        let hit = content.hitTest(root.convert(event.locationInWindow, from: nil))
        return hit === view || hit?.isDescendant(of: view) == true
    }

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

    private func cellSize(of view: PaneTerminalView, rows: Int, columns: Int) -> CGSize {
        CGSize(width: view.frame.width / CGFloat(columns), height: view.frame.height / CGFloat(rows))
    }

    private func update(to point: CGPoint, in view: PaneTerminalView) {
        guard let anchor, let cells = cells(from: anchor, to: point, in: view) else {
            return
        }

        overlay?.frame = rectangle(of: cells, in: view)
    }

    private func finish(at point: CGPoint, in view: PaneTerminalView) {
        defer {
            overlay?.removeFromSuperview()
            overlay = nil
            anchor = nil
        }
        guard let anchor, let cells = cells(from: anchor, to: point, in: view) else {
            return
        }

        copy(cells: cells, in: view)
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
