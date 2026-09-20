import AppKit
@testable import ReviewFeature
import SwiftUI
import Testing

@Suite(.serialized)
struct EditorFindTests {
    // MARK: Internal

    @Test
    func `typing finds the first match after settling and keeps focus`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.type("needle")
        #expect(fixture.view.selectedRange().length == 0)

        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == NSRange(location: 6, length: 6))
        #expect(fixture.field.currentEditor() === fixture.window.firstResponder)
        #expect(fixture.field.currentEditor()?.selectedRange == NSRange(location: 6, length: 0))

        try fixture.type("second")
        try fixture.type("first")
        #expect(fixture.view.selectedRange() == NSRange(location: 6, length: 6))
        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test
    func `clearing or closing find cancels its pending jump`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let selection = fixture.view.selectedRange()
        try fixture.type("needle")
        try fixture.type("")
        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == selection)

        try fixture.type("needle")
        fixture.scroll.isFindBarVisible = false
        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == selection)
    }

    @Test
    func `a query without matches preserves the selection`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let selection = fixture.view.selectedRange()
        try fixture.type("absent")
        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == selection)
    }

    @Test
    func `moving the selection cancels a pending jump`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.type("needle")
        fixture.view.setSelectedRange(NSRange(location: 20, length: 6))
        try await #require(fixture.coordinator.findTask).value
        #expect(fixture.view.selectedRange() == NSRange(location: 20, length: 6))
    }

    // MARK: Private

    private struct Fixture {
        // MARK: Lifecycle

        init() throws {
            _ = NSApplication.shared
            view.string = "first needle\nsecond needle\n"
            view.usesFindBar = true
            view.isIncrementalSearchingEnabled = true
            scroll.documentView = view
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            window.makeFirstResponder(view)
            coordinator.watchFindChanges(of: scroll)
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.showFindInterface.rawValue
            view.performTextFinderAction(action)
            let bar = try #require(scroll.findBarView)
            field = try #require(Self.searchField(in: bar))
        }

        // MARK: Internal

        let view: EditingTextView = .init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let scroll: NSScrollView = .init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window: NSWindow = .init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        let field: NSSearchField
        let coordinator = HighlightingTextEditor.Coordinator(text: .constant(""), language: nil)

        func type(_ query: String) throws {
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.insertText(query, replacementRange: editor.selectedRange())
        }

        func close() {
            window.close()
        }

        // MARK: Private

        private static func searchField(in view: NSView) -> NSSearchField? {
            (view as? NSSearchField) ?? view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
    }
}
