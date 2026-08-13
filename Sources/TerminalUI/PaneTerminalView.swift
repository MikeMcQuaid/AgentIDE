import AgentIDEDomain
import SwiftTerm
import SwiftUI

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

// MARK: - TerminalClipView

/// The scroll view's document: a flipped, clipping window onto the
/// top of the taller terminal, so the scrollable range ends where
/// content ends instead of exposing the blank rows below it.
final class TerminalClipView: NSView {
    // MARK: Lifecycle

    deinit {
        // Nothing beyond subviews to release.
    }

    // MARK: Internal

    override var isFlipped: Bool {
        true
    }
}
