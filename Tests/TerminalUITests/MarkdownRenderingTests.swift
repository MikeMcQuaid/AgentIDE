import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownRenderingTests {
    @Test
    func `changing an image document refreshes its text`() async throws {
        let host = NSHostingView(rootView: MarkdownText(
            "![Missing](file:///nonexistent-agentide-image.png)\n\n"
                + String(repeating: "Previous content. ", count: 100),
        ).frame(width: 400))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let originalHeight = host.fittingSize.height
        host.rootView = MarkdownText("Updated content.").frame(width: 400)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(host.fittingSize.height < originalHeight)
    }

    @Test
    func `code blocks show every line`() async throws {
        func height(_ source: String) async throws -> CGFloat {
            let host = NSHostingView(rootView: MarkdownText(source).frame(width: 400))
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        let multiline = try await height("```swift\nfirst\nsecond\nthird\n```")
        let single = try await height("```swift\nfirst\n```")
        #expect(multiline > single)
    }
}
