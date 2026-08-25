import AgentIDEDomain
import Testing

/// Pins what happens to pane widths dragged on a large display when
/// the window ends up on a small one, which is what unplugging a
/// monitor does.
struct PaneLayoutTests {
    @Test
    func `widths dragged on a large display are left alone where they fit`() {
        let layout = PaneLayout(width: 2_000, sidebar: 300, utility: 700, showsUtility: true)
        #expect(layout.sidebar == 300)
        #expect(layout.utility == 700)
        #expect(layout.showsUtility)
    }

    @Test
    func `the utility pane gives way first, then the sidebar`() {
        // 300 + 700 + 320 needs 1,320; this window has 1,200.
        let narrow = PaneLayout(width: 1_200, sidebar: 300, utility: 700, showsUtility: true)
        #expect(narrow.sidebar == 300)
        #expect(narrow.utility == 580)
        #expect(narrow.showsUtility)

        // Below what the utility pane's own minimum allows, the
        // sidebar narrows too rather than the window overflowing.
        let narrower = PaneLayout(width: 900, sidebar: 400, utility: 700, showsUtility: true)
        #expect(narrower.utility == PaneLayout.utilityRange.lowerBound)
        #expect(narrower.sidebar == 320)
        #expect(narrower.showsUtility)
    }

    @Test
    func `a window too narrow for three panes shows two`() {
        // 130 + 260 + 320 is 710, so 700 cannot hold all three.
        let layout = PaneLayout(width: 700, sidebar: 300, utility: 480, showsUtility: true)
        #expect(layout.showsUtility == false)
        #expect(layout.sidebar == 300)
        // The sidebar still narrows to leave the conversation its
        // own minimum.
        #expect(PaneLayout(width: 500, sidebar: 300, utility: 480, showsUtility: true).sidebar == 180)
    }

    @Test
    func `a hidden utility pane stays hidden and costs nothing`() {
        let layout = PaneLayout(width: 900, sidebar: 300, utility: 900, showsUtility: false)
        #expect(layout.showsUtility == false)
        #expect(layout.sidebar == 300)
    }

    @Test
    func `a window with no width yet changes nothing`() {
        let layout = PaneLayout(width: 0, sidebar: 300, utility: 480, showsUtility: true)
        #expect(layout.sidebar == 300)
        #expect(layout.utility == 480)
        #expect(layout.showsUtility)
    }
}
