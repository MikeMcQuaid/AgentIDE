import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownRenderingTests {
    // MARK: Internal

    @Test
    func `changing an image document refreshes its text`() async throws {
        let image = NSImage(size: NSSize(width: 1, height: 500), flipped: false) { _ in true }
        let data = try #require(image.tiffRepresentation.flatMap { tiff in
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        })
        let host = NSHostingView(rootView: MarkdownText(
            "![Previous image](data:image/png;base64,\(data.base64EncodedString()))\n\nPrevious content.",
        ).frame(width: 400))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        let originalHeight = try await height(host) { $0 > 400 }
        try #require(originalHeight > 400)
        host.rootView = MarkdownText("Updated content.").frame(width: 400)
        let updatedHeight = try await height(host) { $0 > 0 && $0 < originalHeight }
        #expect(updatedHeight > 0 && updatedHeight < originalHeight)
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

    // MARK: Private

    private func height(_ host: some NSView, until ready: (CGFloat) -> Bool) async throws -> CGFloat {
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            let height = host.fittingSize.height
            if ready(height) {
                return height
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }
}
