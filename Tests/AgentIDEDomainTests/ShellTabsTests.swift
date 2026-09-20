@testable import AgentIDEDomain
import Testing

/// What the utility pane's shells do as they are opened, shown and
/// closed, worktree by worktree.
struct ShellTabsTests {
    @Test
    func `a worktree opens as many shells as the work needs`() {
        var tabs = ShellTabs()
        let server = tabs.open(in: "/w/one")
        let calls = tabs.open(in: "/w/one")
        #expect(tabs.shells(in: "/w/one").map(\.title) == ["Shell 1", "Shell 2"])
        // The newest is what the pane shows.
        #expect(tabs.selected(in: "/w/one") == calls)
        #expect(server != calls)
        #expect(tabs.isEmpty == false)
    }

    @Test
    func `each worktree keeps its own shells and its own selection`() {
        var tabs = ShellTabs()
        let first = tabs.open(in: "/w/one")
        let second = tabs.open(in: "/w/two")
        #expect(tabs.shells(in: "/w/one").map(\.id) == [first])
        #expect(tabs.shells(in: "/w/two").map(\.title) == ["Shell 1"])
        #expect(tabs.selected(in: "/w/one") == first)
        #expect(tabs.selected(in: "/w/two") == second)
        // Every shell stays mounted, in the order they were opened.
        #expect(tabs.all.map(\.id) == [first, second])
    }

    @Test
    func `showing one shell leaves the rest running behind it`() {
        var tabs = ShellTabs()
        let first = tabs.open(in: "/w/one")
        tabs.open(in: "/w/one")
        tabs.select(first)
        #expect(tabs.selected(in: "/w/one") == first)
        #expect(tabs.shells(in: "/w/one").count == 2)
        // A shell that has gone cannot be shown.
        tabs.select(999)
        #expect(tabs.selected(in: "/w/one") == first)
    }

    @Test
    func `closing a shell shows the one after it`() {
        var tabs = ShellTabs()
        let first = tabs.open(in: "/w/one")
        let second = tabs.open(in: "/w/one")
        let third = tabs.open(in: "/w/one")
        tabs.select(second)
        tabs.close(second)
        #expect(tabs.selected(in: "/w/one") == third)
        // Closing the last one falls back to the one before it.
        tabs.close(third)
        #expect(tabs.selected(in: "/w/one") == first)
        tabs.close(first)
        #expect(tabs.selected(in: "/w/one") == nil)
        #expect(tabs.isEmpty)
    }

    @Test
    func `closing a shell that is not the shown one changes nothing`() {
        var tabs = ShellTabs()
        let first = tabs.open(in: "/w/one")
        let second = tabs.open(in: "/w/one")
        tabs.close(first)
        #expect(tabs.selected(in: "/w/one") == second)
        #expect(tabs.shells(in: "/w/one").map(\.id) == [second])
    }

    @Test
    func `a new shell fills the gap a closed one left`() {
        var tabs = ShellTabs()
        let first = tabs.open(in: "/w/one")
        tabs.open(in: "/w/one")
        tabs.open(in: "/w/one")
        tabs.close(first)
        tabs.open(in: "/w/one")
        // Numbers are the tab's name for its life, so the rest keep
        // theirs and the newcomer takes the number nobody holds.
        #expect(tabs.shells(in: "/w/one").map(\.title) == ["Shell 2", "Shell 3", "Shell 1"])
    }

    @Test
    func `a destroyed worktree takes its shells with it`() {
        var tabs = ShellTabs()
        tabs.open(in: "/w/one")
        let kept = tabs.open(in: "/w/two")
        tabs.keep(worktreePaths: ["/w/two"])
        #expect(tabs.all.map(\.id) == [kept])
        #expect(tabs.selected(in: "/w/one") == nil)
        #expect(tabs.selected(in: "/w/two") == kept)
    }
}
