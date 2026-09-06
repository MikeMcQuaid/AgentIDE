import Foundation
@testable import ReviewFeature
import Testing

/// Where each file was last scrolled to, kept across editors.
struct EditorScrollPositionsTests {
    @Test
    func `a file comes back where it was, and the oldest fall off`() throws {
        // Named once and removed by that name: the domain a suite is
        // removed by is its name, not its description, and the wrong
        // one left a plist behind on every run.
        let suite = "EditorScrollPositionsTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

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
