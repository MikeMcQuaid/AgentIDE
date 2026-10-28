import AppKit
import SanductorDomain
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct ReviewThreadRowTests {
    // MARK: Internal

    @Test
    func `authors remain selectable outside the conversation toggle`() async throws {
        let host = NSHostingView(rootView: row(resolved: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let author = try #require(descendants(host).first { view in
            (view as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(selectAll) == true
        })
        let authorFrame = author.convert(author.bounds, to: host)
        let parent = unsafe host.superview
        let authorStart = host.convert(NSPoint(x: authorFrame.minX + 1, y: authorFrame.midY), to: parent)
        #expect(host.hitTest(authorStart) === author)
        #expect(window.makeFirstResponder(author))
        #expect(author.tryToPerform(#selector(NSResponder.selectAll(_:)), with: nil))
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        #expect((author as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(copy) == true)
        let collapsedHeight = host.fittingSize.height
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: host.convert(NSPoint(x: 350, y: authorFrame.midY), to: nil),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1,
            ))
            window.sendEvent(event)
        }
        await settle(host) { host.fittingSize.height > collapsedHeight }
        #expect(host.fittingSize.height > collapsedHeight)
    }

    @Test
    func `expanded threads keep authors in the compact header`() async throws {
        let expanded = NSHostingView(rootView: row())
        let collapsed = NSHostingView(rootView: row(resolved: true))
        let comment = NSHostingView(rootView: MarkdownText("A finding to read and copy.\n\nMore context.")
            .frame(width: 464))
        for _ in 0 ..< 10 {
            expanded.layoutSubtreeIfNeeded()
            collapsed.layoutSubtreeIfNeeded()
            comment.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(abs(expanded.fittingSize.height - collapsed.fittingSize.height - comment.fittingSize.height - 8) < 1)
    }

    @Test
    func `marking for resolution collapses the mounted thread and cancelling restores it`() async {
        let host = NSHostingView(rootView: row())
        let resolved = NSHostingView(rootView: row(resolved: true))
        host.layoutSubtreeIfNeeded()
        resolved.layoutSubtreeIfNeeded()
        let expandedHeight = host.fittingSize.height
        let collapsedHeight = resolved.fittingSize.height
        #expect(expandedHeight > collapsedHeight)

        host.rootView = row(pending: true)
        await settle(host) { abs(host.fittingSize.height - collapsedHeight) < 1 }
        #expect(abs(host.fittingSize.height - collapsedHeight) < 1)

        host.rootView = row()
        await settle(host) { abs(host.fittingSize.height - expandedHeight) < 1 }
        #expect(abs(host.fittingSize.height - expandedHeight) < 1)
    }

    // MARK: Private

    private func row(resolved: Bool = false, pending: Bool = false) -> some View {
        ReviewThreadRow(
            thread: ReviewThread(id: "thread", path: "file.swift", line: 1, isResolved: resolved, comments: [
                ReviewThreadComment(author: "reviewer", body: "A finding to read and copy.\n\nMore context."),
            ]),
            isPendingResolution: pending,
        )
        .frame(width: 480)
    }

    private func settle(_ host: some NSView, until ready: () -> Bool) async {
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            if ready() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
