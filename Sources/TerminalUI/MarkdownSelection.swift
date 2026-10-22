import AppKit
import SwiftUI

// MARK: - MarkdownSelection

/// Keeps one active Markdown selection across documents.
struct MarkdownSelection: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            // Textual has no public reset; rebuild only the deselected region.
            .id(generation)
            .background(Region { generation += 1 })
    }

    // MARK: Private

    private struct Region: NSViewRepresentable {
        let clear: () -> Void

        static func dismantleNSView(_ view: MarkdownSelectionRegion, coordinator _: ()) {
            MarkdownSelectionCoordinator.shared.regions.remove(view)
        }

        func makeNSView(context _: Context) -> MarkdownSelectionRegion {
            let view = MarkdownSelectionRegion()
            view.clear = clear
            MarkdownSelectionCoordinator.shared.regions.add(view)
            return view
        }

        func updateNSView(_ view: MarkdownSelectionRegion, context _: Context) {
            view.clear = clear
        }
    }

    @State private var generation = 0
}

// MARK: - MarkdownSelectionRegion

/// A passive marker: Textual continues to receive every mouse and key event.
final class MarkdownSelectionRegion: NSView {
    // MARK: Lifecycle

    deinit {
        // The coordinator holds regions weakly.
    }

    // MARK: Internal

    var clear: (() -> Void)?
    var selected = false

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - MarkdownSelectionCoordinator

final class MarkdownSelectionCoordinator {
    // MARK: Lifecycle

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.mouseDown(event)
            return event
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: Internal

    static let shared: MarkdownSelectionCoordinator = .init()

    let regions: NSHashTable<MarkdownSelectionRegion> = .weakObjects()

    func mouseDown(_ event: NSEvent) {
        for region in regions.allObjects {
            let window = unsafe region.window
            let contains = window === event.window
                && region.bounds
                .intersection(region.visibleRect)
                .contains(region.convert(event.locationInWindow, from: nil))
            if region.selected, contains == false {
                region.clear?()
            }
            region.selected = contains
        }
    }

    // MARK: Private

    private var monitor: Any?
}
