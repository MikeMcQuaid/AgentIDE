import AgentIDEDomain
import AppKit
import SwiftTerm

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour. Agent
/// panes feed it from a herdr terminal stream and never start a
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

    /// Routes the wheel to herdr for agent panes: scrollback lives
    /// in the server, which repaints the viewport scrolled, so the
    /// local buffer (only ever the rendered screen) never scrolls.
    var onScroll: ((_ upwards: Bool, _ lines: Int) -> Void)?

    /// Takes the files a paste carries, staged and typed the way a
    /// drop is; nil leaves every paste to the terminal.
    var onPasteFiles: (([URL]) -> Bool)?

    /// Whether a paste is wrapped in bracketed-paste markers here
    /// regardless of what the local terminal believes: a herdr pane's
    /// frames carry the rendered screen and never the modes the agent
    /// set, so the terminal never learns bracketed paste is on and a
    /// paste went as keystrokes, every newline submitting what came
    /// before it. Agents and shells alike accept the markers.
    var bracketsPastes = false

    /// Reads the pane's whole recent output, for agent panes whose
    /// local buffer holds only the rendered screen: a selection can
    /// never cover what was scrolled past, this can. Nil hides the
    /// menu item.
    var onCopyAllOutput: (() async -> String?)?

    /// Keeps a selection while output arrives. SwiftTerm drops the
    /// selection on every line feed whenever mouse reporting is on,
    /// which it always is here so that an agent's own scrolling and
    /// pagers work, and an agent writing a long answer feeds a line
    /// at a time: selecting anything while one was thinking was
    /// therefore impossible. Nothing is lost by keeping it, since
    /// SwiftTerm already moves a selection with the text it covers,
    /// and that is exactly what it does when mouse reporting is off.
    override func linefeed(source: Terminal) {
        guard selectionActive else {
            super.linefeed(source: source)
            return
        }
    }

    /// Rounds a drag's end to the boundary nearest the pointer.
    /// SwiftTerm names the cell the pointer is inside and takes the
    /// end as exclusive, so the character under the pointer was left
    /// out of the highlight and the copy alike: every drag across a
    /// word dropped its last letter unless it carried on into the
    /// next one. A word or line drag (`clickCount` above one) picks
    /// its own boundaries and is left alone.
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        roundSelectionEnd(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        roundSelectionEnd(at: event)
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
        if onCopyAllOutput != nil {
            menu.addItem(.separator())
            let allItem = NSMenuItem(title: "Copy All Output", action: #selector(copyAllOutput(_:)), keyEquivalent: "")
            allItem.target = self
            menu.addItem(allItem)
        }
        return menu
    }

    /// A paste of files or an image goes to the agent as a drop
    /// would; anything else pastes as text.
    override func paste(_ sender: Any?) {
        let files = Self.pastedFiles()
        if let onPasteFiles, files.isEmpty == false, onPasteFiles(files) {
            return
        }

        if bracketsPastes, getTerminal().bracketedPasteMode == false,
           let text = NSPasteboard.general.string(forType: .string)
        {
            // Three sends, gathered into one write by the coordinator,
            // so the agent sees one paste and draws one.
            send(data: Self.bracketedPasteStart[...])
            send(txt: text)
            send(data: Self.bracketedPasteEnd[...])
            return
        }
        super.paste(sender as Any)
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

    /// One character cell, the size the terminal itself draws it.
    /// Dividing the pane by its rows is not the same thing: the grid
    /// is laid out from the top in whole cells of the font's own
    /// size and whatever is left over sits unused at the bottom, so
    /// a measurement against the pane drifts further from the text
    /// with every row down the screen. The optimal frame is exactly
    /// one cell by the grid, plus the width SwiftTerm reserves for a
    /// scroller it is showing; measuring against the full width put
    /// every column a cell right and copied blanks.
    static func cellSize(of view: PaneTerminalView) -> CGSize {
        let terminal = view.getTerminal()
        let rows = max(terminal.rows, 1)
        let columns = max(terminal.cols, 1)
        let optimal = view.getOptimalFrameSize().size
        guard optimal.width > 0, optimal.height > 0 else {
            return CGSize(width: view.frame.width / CGFloat(columns), height: view.frame.height / CGFloat(rows))
        }

        let scroller = view.subviews.compactMap { $0 as? NSScroller }.first { $0.isHidden == false }
        let gridWidth = optimal.width - (scroller?.frame.width ?? 0)
        return CGSize(width: gridWidth / CGFloat(columns), height: optimal.height / CGFloat(rows))
    }

    /// Sends Option and an arrow as terminals always have, for a
    /// program that never asked for the kitty keyboard protocol:
    /// SwiftTerm now encodes them the way that protocol does whether
    /// or not anything turned it on, and a shell typed the tail of
    /// the sequence into the line rather than moving a word. Fed by
    /// the coordinator's event monitor, since `keyDown` is not
    /// overridable either; nil means the pane consumed it.
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard window?.firstResponder === self,
              getTerminal().keyboardEnhancementFlags.isEmpty,
              event.modifierFlags.isDisjoint(with: [.command, .control]),
              event.modifierFlags.contains(.option),
              let arrow = Self.arrow(of: event)
        else {
            return event
        }

        send(TerminalKeys.optionArrow(arrow, applicationCursor: getTerminal().applicationCursor))
        return nil
    }

    /// The whole recent output from herdr, reflowed like a selection
    /// copy when this pane reflows, onto the clipboard.
    @objc
    func copyAllOutput(_: Any?) {
        guard let onCopyAllOutput else {
            return
        }

        Task { @MainActor in
            guard let text = await onCopyAllOutput() else {
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(reflowsCopies ? PasteableText.reflow(text) : text, forType: .string)
        }
    }

    /// Routes one wheel event to herdr when this pane owns the
    /// wheel and the pointer is over it; nil means it was consumed.
    /// Fed by the coordinator's event monitor, since SwiftTerm's
    /// wheel handling is not overridable outside its module. The
    /// delta translates into whole terminal lines: precise trackpad
    /// deltas accumulate against the cell height, while classic
    /// wheel notches already arrive in line units.
    func routeWheel(_ event: NSEvent) -> NSEvent? {
        // Every mounted pane watches the wheel, and panes stack: a
        // hidden shell or another worktree's terminal can hold the
        // same frame as the one being scrolled. Only the view the
        // window would actually hit takes the event, and only once,
        // however many monitors see it: scrolling twice asked herdr
        // for two repaints, which arrived as the same lines twice.
        guard let onScroll, event.window === window,
              let hit = window?.contentView?.hitTest(event.locationInWindow),
              hit === self || hit.isDescendant(of: self),
              Self.claim(event)
        else {
            return event
        }

        let rows = CGFloat(getTerminal().rows)
        let cellHeight = rows > 0 ? bounds.height / rows : 0
        var lines = 0
        if event.hasPreciseScrollingDeltas, cellHeight > 0 {
            wheelRemainder += event.scrollingDeltaY
            lines = Int(wheelRemainder / cellHeight)
            wheelRemainder -= CGFloat(lines) * cellHeight
        } else {
            lines = Int(event.scrollingDeltaY.rounded())
        }
        if lines != 0 {
            onScroll(lines > 0, abs(lines))
        }
        return nil
    }

    /// Gives up the local scrollback: herdr owns an agent pane's
    /// history and repaints the whole screen for every scroll, so
    /// each repaint pushed the screen it replaced into SwiftTerm's
    /// own history and the same output turned up two and three
    /// times over. Nothing is lost, since scrolling asks herdr,
    /// which has the real thing.
    func dropLocalScrollback() {
        getTerminal().changeScrollback(nil)
    }

    /// Hides the scroll indicator. An agent pane's scrollback lives
    /// in herdr, which owns the scrolling, so the knob never moves
    /// and only takes up room; SwiftTerm gives the reserved width
    /// back to the terminal once it is hidden.
    func hideScroller() {
        for scroller in subviews.compactMap({ $0 as? NSScroller }) {
            scroller.isHidden = true
        }
    }

    // MARK: Private

    /// `ESC [ 200 ~` and `ESC [ 201 ~`, spelt here because SwiftTerm's
    /// own are mutable statics strict concurrency refuses.
    private static let bracketedPasteStart: Array = .init("\u{1B}[200~".utf8)
    private static let bracketedPasteEnd: Array = .init("\u{1B}[201~".utf8)

    /// The last wheel event any pane handled, so a second monitor
    /// seeing the same event does nothing with it.
    private static var lastWheel: (timestamp: TimeInterval, window: Int)?

    /// The wheel's fractional line carry between events.
    private var wheelRemainder: CGFloat = 0

    /// Which arrow an event is, if it is one.
    private static func arrow(of event: NSEvent) -> TerminalKeys.Arrow? {
        guard let key = event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) })
        else {
            return nil
        }

        switch key {
        case NSLeftArrowFunctionKey:
            return .left

        case NSRightArrowFunctionKey:
            return .right

        case NSUpArrowFunctionKey:
            return .upward

        case NSDownArrowFunctionKey:
            return .downward

        default:
            return nil
        }
    }

    /// Whether this pane is the first to take the event.
    private static func claim(_ event: NSEvent) -> Bool {
        let identity = (timestamp: event.timestamp, window: event.windowNumber)
        guard lastWheel?.timestamp != identity.timestamp || lastWheel?.window != identity.window else {
            return false
        }

        lastWheel = identity
        return true
    }

    /// See `mouseDragged`: the end column SwiftTerm chose, moved on
    /// to the nearer boundary when the pointer is past the middle of
    /// its cell. Never moved backwards, so this can only ever add the
    /// character the pointer is on.
    private func roundSelectionEnd(at event: NSEvent) {
        guard event.clickCount <= 1, let selection, selection.active else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let terminal = getTerminal()
        guard let column = TerminalSelection.endColumn(
            across: point.x,
            cellWidth: Self.cellSize(of: self).width,
            columns: terminal.cols,
        ), column > selection.end.col else {
            return
        }

        selection.dragExtend(bufferPosition: Position(col: column, row: selection.end.row))
    }
}
