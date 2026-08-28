import AppKit

extension NSView {
    /// Whether this view is actually visible: not hidden and not
    /// faded out, itself or through any view above it. A pane kept
    /// mounted behind another is transparent rather than hidden,
    /// which `isHiddenOrHasHiddenAncestor` alone does not catch.
    var isOnScreen: Bool {
        var current: NSView? = self
        while let view = current {
            if view.isHidden || view.alphaValue <= 0 {
                return false
            }

            current = view.superview
        }
        return true
    }
}
