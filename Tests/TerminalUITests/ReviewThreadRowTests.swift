import AgentIDEDomain
import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct ReviewThreadRowTests {
    // MARK: Internal

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
