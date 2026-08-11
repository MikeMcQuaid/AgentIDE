import AppKit
import SwiftUI

/// The behind-window sidebar blur, provided directly now that the
/// sidebar is a plain split pane rather than a navigation split
/// view column.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {
        // The material never changes after creation.
    }
}
