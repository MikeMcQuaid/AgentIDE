import AppKit
import SwiftUI

// MARK: - TooltipSurface

/// A click-through AppKit view carrying a system tooltip.
private struct TooltipSurface: NSViewRepresentable {
    // MARK: Internal

    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = ClickThroughView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.toolTip = text
    }

    // MARK: Private

    private final class ClickThroughView: NSView {
        // MARK: Lifecycle

        deinit {
            // Nothing to clean up.
        }

        // MARK: Internal

        override func hitTest(_: NSPoint) -> NSView? {
            // Tooltips use their own tracking; clicks fall through.
            nil
        }
    }
}

// MARK: - HoverHelp

public extension View {
    /// An explanatory tooltip on hover. SwiftUI's `.help` is applied
    /// too, but the AppKit tooltip is the one that reliably shows on
    /// the current macOS beta.
    func hoverHelp(_ text: String) -> some View {
        help(text).overlay(TooltipSurface(text: text))
    }
}
