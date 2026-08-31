import AppKit
@testable import ReviewFeature
import SwiftUI
import Testing

/// The editor's recovery from a display switch, which can leave the
/// AppKit scroll view on the old screen's geometry while SwiftUI's
/// own chrome lays out correctly.
struct HighlightingTextEditorTests {
    @Test
    func `a display change snaps the editor back to its container`() async {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        // The frame a monitor switch left behind: shifted off the
        // pane and wider than it, bleeding under neighbours.
        let scroll = NSScrollView(frame: NSRect(x: -500, y: 0, width: 1_200, height: 200))
        container.addSubview(scroll)
        let coordinator = HighlightingTextEditor.Coordinator(text: .constant(""), language: nil)
        coordinator.watchDisplayChanges(of: scroll)

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        // The snap waits a turn for layout to settle.
        for _ in 0 ..< 20 where scroll.frame != container.bounds {
            await Task.yield()
        }
        #expect(scroll.frame == container.bounds)
    }

    @Test
    func `an editor already in place is left alone`() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let scroll = NSScrollView(frame: container.bounds)
        container.addSubview(scroll)
        let coordinator = HighlightingTextEditor.Coordinator(text: .constant(""), language: nil)
        coordinator.watchDisplayChanges(of: scroll)

        coordinator.realignAfterDisplayChange()
        #expect(scroll.frame == container.bounds)
    }
}
