import AppKit
import SwiftUI

/// Read-only text that selects like a document: one text view over
/// a whole log, so a drag crosses entries, Cmd-F finds within it and
/// links open where every other link in the app does.
public struct SelectableTextView: NSViewRepresentable {
    // MARK: Lifecycle

    /// Creates the view over the attributed text it shows.
    public init(text: NSAttributedString) {
        self.text = text
    }

    // MARK: Public

    /// Routes clicked links the way the rest of the app does: web
    /// links only, Cmd deciding the browser.
    public final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        deinit {
            // Nothing to clean up.
        }

        // MARK: Public

        public func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
            guard let url = link as? URL else {
                return false
            }

            LinkOpener.open(url.absoluteString)
            return true
        }
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.autoresizingMask = .width
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.delegate = context.coordinator
        view.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = view
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context _: Context) {
        guard let view = scroll.documentView as? NSTextView,
              view.textStorage?.isEqual(to: text) == false
        else {
            return
        }

        // A selection survives new entries when it still fits, so a
        // message landing mid-drag does not take the copy away.
        let selected = view.selectedRange()
        view.textStorage?.setAttributedString(text)
        if NSMaxRange(selected) <= text.length {
            view.setSelectedRange(selected)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: Private

    private static let inset: CGFloat = 8

    private let text: NSAttributedString
}
