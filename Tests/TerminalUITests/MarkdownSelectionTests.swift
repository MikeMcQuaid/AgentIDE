import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
@Suite(.serialized)
struct MarkdownSelectionTests {
    // MARK: Internal

    @Test(arguments: ["First paragraph.\n\nSecond paragraph.", "### Heading", "1. First\n2. Second"])
    func `rendered Markdown accepts selection and copy across its width`(markdown: String) async throws {
        let host = NSHostingView(rootView: MarkdownText(markdown)
            .frame(width: 400, alignment: .leading))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")
        var selectable: NSView?
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            selectable = descendants(host).first { view in
                String(describing: type(of: view)).contains("NSTextInteractionView")
                    && (view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(selectAll) == true
            }
            if selectable != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let view = try #require(selectable)
        #expect(host.hitTest(view.convert(NSPoint(x: 5, y: 5), to: host)) === view)
        let bounds = view.convert(view.bounds, to: host)
        #expect(host.hitTest(NSPoint(x: 399, y: bounds.midY)) === view)
        #expect(host.hitTest(NSPoint(x: 1, y: bounds.midY)) === view)
        #expect(window.makeFirstResponder(view))
        try view.mouseDown(with: mouseEvent(
            .leftMouseDown, point: NSPoint(x: 399, y: bounds.midY), host: host, window: window,
        ))
        try view.mouseDragged(with: mouseEvent(
            .leftMouseDragged, point: NSPoint(x: 1, y: bounds.midY), host: host, window: window,
        ))
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        #expect((view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(copy) == true)
        #expect(view.responds(to: #selector(NSText.copy(_:))))
    }

    @Test
    func `selecting another Markdown region clears the previous selection`() async throws {
        let host = NSHostingView(rootView: VStack {
            MarkdownText("First comment")
            MarkdownText("Second comment")
        }.frame(width: 400, height: 400))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            if descendants(host).count(where: { view in
                (view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(selectAll) == true
            }) == 2 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        for index in 0 ..< 2 {
            let views = descendants(host).filter { view in
                (view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(selectAll) == true
            }
            #expect(views.count == 2)
            let view = try #require(views.dropFirst(index).first)
            let point = view.convert(NSPoint(x: 10, y: view.bounds.midY), to: host)
            let down = try mouseEvent(.leftMouseDown, point: point, host: host, window: window)
            #expect(down.window === window)
            let parent = unsafe host.superview
            #expect(host.hitTest(host.convert(point, to: parent)) === view)
            MarkdownSelectionCoordinator.shared.mouseDown(down)
            view.mouseDown(with: down)
            try view.mouseUp(with: mouseEvent(.leftMouseUp, point: point, host: host, window: window))
            #expect(window.firstResponder === view)
            #expect(view.tryToPerform(#selector(NSResponder.selectAll(_:)), with: nil))
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            let selectedCount = descendants(host).count { view in
                (view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(copy) == true
            }
            #expect(selectedCount == 1)
        }
    }

    // MARK: Private

    private func mouseEvent(
        _ type: NSEvent.EventType,
        point: NSPoint,
        host: NSView,
        window: NSWindow,
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: host.convert(point, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
