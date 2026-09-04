@testable import AgentIDEDomain
import Foundation
import Testing

/// When a pane's process tree is worth saying something about.
struct PaneLoadTests {
    @Test
    func `a busy spell starts when the tree gets busy and ends when it stops`() {
        let start = Date()
        // Quiet trees have no spell at all.
        #expect(PaneLoad.busySince(nil, percent: 40, now: start) == nil)
        // Three cores starts one.
        let since = PaneLoad.busySince(nil, percent: 320, now: start)
        #expect(since == start)
        // Still busy a minute later keeps the moment it began, which
        // is what tells a build from a runaway.
        let later = start.addingTimeInterval(60)
        #expect(PaneLoad.busySince(since, percent: 700, now: later) == start)
        // Dropping back ends it, so the next spell is its own.
        #expect(PaneLoad.busySince(since, percent: 20, now: later) == nil)
    }

    @Test
    func `only a spell that has lasted is worth showing`() {
        let start = Date()
        let load = PaneLoad(percent: 707, busiest: "actionlint", since: start)

        // A parallel build, and a repository's own test suite, pass
        // three cores at once and finish; nothing is said about them.
        #expect(load.isHeavy(now: start.addingTimeInterval(60)) == false)
        #expect(load.isHeavy(now: start.addingTimeInterval(9 * 60)) == false)
        #expect(load.isHeavy(now: start.addingTimeInterval(11 * 60)))
    }

    @Test
    func `the summary names what is running and for how long`() {
        let start = Date()
        let load = PaneLoad(percent: 707, busiest: "actionlint", since: start)
        let summary = load.summary(now: start.addingTimeInterval(12 * 60))

        #expect(summary == "actionlint has held 707% of the CPU here for 12 minutes")
        // A single minute reads as one, and a spell shorter than one
        // still counts as a minute rather than none.
        #expect(load.summary(now: start.addingTimeInterval(70)).hasSuffix("for 1 minute"))
    }
}
