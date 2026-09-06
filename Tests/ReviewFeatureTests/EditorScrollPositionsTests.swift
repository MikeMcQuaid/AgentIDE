import Foundation
@testable import ReviewFeature
import Testing

/// Where each file was last scrolled to, kept across editors.
struct EditorScrollPositionsTests {
    @Test
    func `a file comes back where it was, and the oldest fall off`() throws {
        let defaults = try #require(UserDefaults(suiteName: "EditorScrollPositionsTests-" + UUID().uuidString))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        #expect(EditorScrollPositions.position(for: "/w/a.swift", in: defaults) == nil)
        EditorScrollPositions.remember(CGPoint(x: 0, y: 240), for: "/w/a.swift", in: defaults)
        #expect(EditorScrollPositions.position(for: "/w/a.swift", in: defaults) == CGPoint(x: 0, y: 240))

        // Scrolling again replaces, rather than adding a second entry.
        EditorScrollPositions.remember(CGPoint(x: 0, y: 12), for: "/w/a.swift", in: defaults)
        #expect(EditorScrollPositions.position(for: "/w/a.swift", in: defaults) == CGPoint(x: 0, y: 12))

        // Enough newer files push the first one off the end.
        for number in 0 ..< EditorScrollPositions.capacity {
            EditorScrollPositions.remember(CGPoint(x: 0, y: 1), for: "/w/\(number).swift", in: defaults)
        }
        #expect(EditorScrollPositions.position(for: "/w/a.swift", in: defaults) == nil)
        #expect(EditorScrollPositions.position(for: "/w/0.swift", in: defaults) != nil)
    }
}
