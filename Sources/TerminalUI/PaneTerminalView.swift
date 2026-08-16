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

            // Cells never written hold NUL; the pasteboard must carry
            // spaces there, as SwiftTerm's own copy does, or a pasted
            // script arrives peppered with ^@ where its indentation
            // and word gaps were.
            let text = line.translateToString(trimRight: true, startCol: left, endCol: right + 1)
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
