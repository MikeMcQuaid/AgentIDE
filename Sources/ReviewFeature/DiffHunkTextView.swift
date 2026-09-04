import AppKit
import SwiftUI

// NSTextView ranges are UTF-16 offsets, so NSString is the correct
// arithmetic here, not String.
// swiftlint:disable legacy_objc_type

// MARK: - DiffHunkClipboard

/// The selectable hunk's copy arithmetic: what leaves on the
/// clipboard is the code alone, each line's gutter stripped, so a
/// drag copy pastes character-exact.
enum DiffHunkClipboard {
    /// The selected slice with every line's leading gutter removed.
    static func stripped(_ text: String, selection: NSRange, gutterLength: Int) -> String {
        let whole = text as NSString
        var pieces = ""
        var location = selection.location
        while location < NSMaxRange(selection), location < whole.length {
            let line = whole.lineRange(for: NSRange(location: location, length: 0))
            let code = NSRange(
                location: min(line.location + gutterLength, NSMaxRange(line)),
                length: max(0, line.length - gutterLength),
            )
            let visible = NSIntersectionRange(selection, code)
            if visible.length > 0 {
                pieces += whole.substring(with: visible)
            }
            location = NSMaxRange(line)
        }
        return pieces
    }
}

// MARK: - DiffHunkTextView

/// A read-only hunk as one text view, so a drag selects across
/// lines the way it cannot across a stack of texts. The gutter
/// rides inside the text but never inside a copy, and clicking a
/// changed line's gutter still toggles it for rejection.
struct DiffHunkTextView: NSViewRepresentable {
    /// The hunk with gutters embedded, one line per paragraph.
    let text: NSAttributedString

    /// The gutter's length in characters, identical on every line.
    let gutterLength: Int

    /// The zero-based lines whose gutter click toggles rejection.
    let changedLines: Set<Int>

    let onToggleLine: (Int) -> Void

    func makeNSView(context _: Context) -> HunkTextView {
        let view = HunkTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = []
        return view
    }

    func updateNSView(_ view: HunkTextView, context _: Context) {
        view.gutterLength = gutterLength
        view.changedLines = changedLines
        view.onToggleLine = onToggleLine
        if view.textStorage?.isEqual(to: text) == false {
            view.textStorage?.setAttributedString(text)
        }
    }

    func makeCoordinator() -> HunkMeasurer {
        HunkMeasurer()
    }

    /// Measured off the view: laying out its own container resizes
    /// it, and a measurement that resizes what it measures loops
    /// until AppKit kills the window (see AGENTS.md).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: HunkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        return CGSize(width: width, height: context.coordinator.height(of: text, width: width))
    }
}

// MARK: - HunkMeasurer

/// A layout stack with no view attached, so laying it out resizes
/// nothing. One per hunk, held as its coordinator, so hunks do not
/// evict each other's layout.
final class HunkMeasurer {
    // MARK: Lifecycle

    deinit {
        // The layout stack owns nothing outside itself.
    }

    init() {
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }

    // MARK: Internal

    func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        if measured !== text {
            storage.setAttributedString(text)
            measured = text
        }

        if container.size.width != width {
            container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        }

        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    // MARK: Private

    private let storage: NSTextStorage = .init()
    private let layout: NSLayoutManager = .init()
    private let container: NSTextContainer = .init(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

    /// Compared by identity, since hunks are memoised by content
    /// upstream and an equal instance costs only a relayout.
    private var measured: NSAttributedString?
}

// MARK: - HunkTextView

/// The text view behind a selectable hunk: copies strip the gutter,
/// gutter clicks on changed lines toggle rejection, and the review
/// pane's own find bar keeps Cmd-F rather than this view swallowing
/// it.
final class HunkTextView: NSTextView {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    var gutterLength = 0
    var changedLines: Set<Int> = []
    var onToggleLine: (Int) -> Void = { _ in
        // Replaced by the representable's update.
    }

    /// The diff is searched by the review pane's own bar, which the
    /// window falls back to when nothing answers Cmd-F; a focused
    /// hunk must not answer it with nothing. Nonisolated to match
    /// `NSObject`, which AppKit drives on the main thread anyway.
    override nonisolated func responds(to selector: Selector?) -> Bool {
        if selector == #selector(NSResponder.performTextFinderAction(_:)) {
            return false
        }
        return super.responds(to: selector)
    }

    override func copy(_: Any?) {
        let selected = selectedRange()
        guard selected.length > 0 else {
            return
        }

        let code = DiffHunkClipboard.stripped(string, selection: selected, gutterLength: gutterLength)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let layout = layoutManager, let container = textContainer else {
            super.mouseDown(with: event)
            return
        }

        let index = layout.characterIndex(
            for: inContainer,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil,
        )
        let text = string as NSString
        guard index < text.length else {
            super.mouseDown(with: event)
            return
        }

        let line = text.lineRange(for: NSRange(location: index, length: 0))
        let lineIndex = text.substring(to: line.location).components(separatedBy: "\n").count - 1
        if index - line.location < gutterLength, changedLines.contains(lineIndex) {
            onToggleLine(lineIndex)
            return
        }

        super.mouseDown(with: event)
    }
}

// swiftlint:enable legacy_objc_type
