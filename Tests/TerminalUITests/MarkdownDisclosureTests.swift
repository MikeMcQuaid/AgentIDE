import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownDisclosureTests {
    @Test
    func `collapsed bot sections use compact spacing`() async throws {
        let disclosure = "<details><summary>Review info</summary>Metadata.</details>"
        let host = NSHostingView(rootView: MarkdownText(disclosure + "\n\n" + disclosure).frame(width: 600))
        let single = NSHostingView(rootView: MarkdownText(disclosure).frame(width: 600))
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            single.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(abs(host.fittingSize.height - 2 * single.fittingSize.height - 8) < 1)
    }

    @Test
    func `review rules have no more spacing than paragraphs`() async throws {
        let host = NSHostingView(rootView: MarkdownText("Posted findings.\n\n---\n\nReview info.").frame(width: 600))
        let paragraph = NSHostingView(rootView: MarkdownText("Posted findings.").frame(width: 600))
        let rule = NSHostingView(rootView: MarkdownText("---").frame(width: 600))
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            paragraph.layoutSubtreeIfNeeded()
            rule.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(abs(host.fittingSize.height - 2 * paragraph.fittingSize.height - rule.fittingSize.height - 32) < 1)
    }

    @Test(arguments: [
        "<!-- review metadata -->",
        "<div><!-- review metadata --></div>",
        "<script>hidden()</script><style>body { color: red }</style>",
    ])
    func `hidden markup adds no gaps around disclosures`(hidden: String) async throws {
        let blocks = [
            "<details><summary>Summary</summary>Change summary.</details>",
            "**Priority:** Normal",
            "<details><summary>Merge risk: Moderate</summary>Review metadata.</details>",
            "<details><summary>Pre-merge checks: Passed 4</summary>Check results.</details>",
        ]
        let source = hidden + "\n\n" + blocks.joined(separator: "\n\n" + hidden + "\n\n") + "\n\n" + hidden
        #expect(MarkdownText.parsedChunks(hidden).isEmpty)
        #expect(MarkdownText.parsedChunks(source).count == blocks.count)
        let host = NSHostingView(rootView: MarkdownText(source).frame(width: 600))
        let baseline = NSHostingView(rootView: MarkdownText(blocks.joined(separator: "\n\n")).frame(width: 600))
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            baseline.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(baseline.fittingSize.height > 0)
        #expect(abs(host.fittingSize.height - baseline.fittingSize.height) < 1)
    }
}
