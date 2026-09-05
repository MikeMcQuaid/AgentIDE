@testable import AgentIDEData
import Testing

/// What a directory of your own last said, kept so nothing touches
/// it again until you look at it.
struct HostFactsTests {
    @Test
    func `a directory nobody has read has nothing to say`() {
        #expect(HostFactsCache().facts(of: "/Users/someone/Documents/notes") == nil)
    }

    @Test
    func `the last reading answers for a directory nobody is looking at`() {
        let cache = HostFactsCache()
        let read = HostFacts(exists: true, branch: "main", isDirty: true, aheadOfUpstream: 2)
        cache.remember(read, of: "/Volumes/share/work")

        // The row paints from this rather than from a stat that
        // would ask macOS, and the user, all over again.
        #expect(cache.facts(of: "/Volumes/share/work") == read)

        // A directory that has gone is remembered as gone, so its
        // row stops being drawn without anything touching it.
        let gone = HostFacts(exists: false, branch: "", isDirty: false, aheadOfUpstream: nil)
        cache.remember(gone, of: "/Volumes/share/work")
        #expect(cache.facts(of: "/Volumes/share/work")?.exists == false)
    }
}
