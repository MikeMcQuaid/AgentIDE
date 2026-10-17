import AgentIDEDomain
import AppKit
import SwiftTerm

// MARK: - PaneTerminalView

/// The SwiftTerm view with the pane's own copy behaviour. Agent
/// panes feed it from a herdr terminal stream and never start a
/// process; the shell pane starts a plain local shell on its PTY.
final class PaneTerminalView: TerminalView {
    // MARK: Lifecycle

    deinit {
        // A local shell's PTY dies with the view; control channels
        // are owned by the coordinator.
    }

    // MARK: Internal

    /// The local shell's PTY, absent from herdr-backed panes.
    var process: LocalProcess?

    /// Reflows multi-line copies for pasting into prose tools.
    var reflowsCopies = false

    /// Destination for selection copies, isolated from the clipboard in tests.
    var copyPasteboard: NSPasteboard = .general

    /// The held Option-drag block, until a new selection replaces it.
    var selectedBlockText: String?

    /// Clears the rectangular selection when native selection takes over.
    var onNativeSelection: (() -> Void)?

    /// Routes the wheel and pointer cell to herdr, which scrolls
    /// its history or forwards mouse input to the agent.
    var onScroll: ((_ upwards: Bool, _ lines: Int, _ column: Int, _ row: Int) -> Void)?

    /// Takes the files a paste carries, staged and typed the way a
    /// drop is; nil leaves every paste to the terminal.
    var onPasteFiles: (([URL]) -> Bool)?

    /// herdr frames omit the agent's input modes, so pastes need
    /// brackets and modified keys must bypass the shell mapping.
    var isHerdrBacked = false

    /// Reads the pane's whole recent output, for agent panes whose
    /// local buffer holds only the rendered screen: a selection can
    /// never cover what was scrolled past, this can. Nil hides the
    /// menu item.
    var onCopyAllOutput: (() async -> String?)?

    /// Discards the herdr client and attaches afresh, for a pane
    /// that stopped drawing; nil on a local shell, which has none.
    var onReattach: (() -> Void)?

    /// Round native drags through the view's input API, without escaping
    /// SwiftTerm's locked selection state.
    override func mouseDown(with event: NSEvent) {
        selectionPress = event
        super.mouseDown(with: event)
        if selectionActive {
            onNativeSelection?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let press = selectionPress {
            guard event.locationInWindow != press.locationInWindow else {
                return
            }

            selectionPress = nil
            let rounded = roundedSelectionEvent(press)
            if rounded !== press {
                super.mouseDown(with: rounded)
            }
        }
        super.mouseDragged(with: roundedSelectionEvent(event))
        if selectionActive {
            onNativeSelection?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        selectionPress = nil
        super.mouseUp(with: event)
        if selectionActive {
            onNativeSelection?()
        }
    }

    override nonisolated func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        // The callback holds SwiftTerm's lock; read selection after it returns.
        Task { @MainActor [weak self] in
            if self?.selectionActive == true {
                self?.onNativeSelection?()
            }
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
        if onCopyAllOutput != nil {
            menu.addItem(.separator())
            let allItem = NSMenuItem(title: "Copy All Output", action: #selector(copyAllOutput(_:)), keyEquivalent: "")
            allItem.target = self
            menu.addItem(allItem)
        }
        if onReattach != nil {
            menu.addItem(.separator())
            let reattachItem = NSMenuItem(title: "Reattach", action: #selector(reattach(_:)), keyEquivalent: "")
            reattachItem.target = self
            menu.addItem(reattachItem)
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

        if isHerdrBacked, terminalStateSnapshot().bracketedPasteMode == false,
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

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)), selectedBlockText != nil {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// A block stays rectangular; native selection reflows in prose panes.
    override func copy(_: Any) {
        var text = getSelection() ?? selectedBlockText ?? ""
        if reflowsCopies || isHerdrBacked {
            text = selectionActive && reflowsCopies ? PasteableText.reflow(text) : PasteableText.cleanTerminalCopy(text)
        }
        copyPasteboard.clearContents()
        copyPasteboard.setString(text, forType: .string)
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
        let terminal = view.terminalDimensions
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

            copyPasteboard.clearContents()
            copyPasteboard.setString(
                reflowsCopies ? PasteableText.reflow(text) : PasteableText.cleanTerminalCopy(text), forType: .string,
            )
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
        guard let onScroll, unsafe event.window === window,
              let hit = unsafe window?.contentView?.hitTest(event.locationInWindow),
              hit === self || hit.isDescendant(of: self),
              Self.claim(event)
        else {
            return event
        }

        let rows = CGFloat(terminalDimensions.rows)
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
            let point = convert(event.locationInWindow, from: nil)
            let cell = Self.cellSize(of: self)
            onScroll(
                lines > 0,
                abs(lines),
                min(max(Int(point.x / cell.width), 0), terminalDimensions.cols - 1),
                min(max(Int((bounds.height - point.y) / cell.height), 0), terminalDimensions.rows - 1),
            )
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
        changeScrollback(nil)
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

    private var selectionPress: NSEvent?

    /// The wheel's fractional line carry between events.
    private var wheelRemainder: CGFloat = 0

    /// Whether this pane is the first to take the event.
    private static func claim(_ event: NSEvent) -> Bool {
        let identity = (timestamp: event.timestamp, window: event.windowNumber)
        guard lastWheel?.timestamp != identity.timestamp || lastWheel?.window != identity.window else {
            return false
        }

        lastWheel = identity
        return true
    }

    @objc
    private func reattach(_: Any?) {
        onReattach?()
    }

    private func roundedSelectionEvent(_ event: NSEvent) -> NSEvent {
        guard event.clickCount == 1, currentMouseMode == .off || allowMouseReporting == false else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        let cell = Self.cellSize(of: self)
        guard let column = TerminalSelection.endColumn(
            across: point.x, cellWidth: cell.width, columns: terminalDimensions.cols,
        ) else {
            return event
        }

        return NSEvent.mouseEvent(
            with: event.type,
            location: convert(NSPoint(x: CGFloat(column) * cell.width, y: point.y), to: nil),
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure,
        ) ?? event
    }
}
