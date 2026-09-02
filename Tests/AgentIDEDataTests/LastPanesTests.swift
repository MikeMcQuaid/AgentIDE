@testable import AgentIDEData
import Foundation
import Testing

/// The hold over herdr's last pane listing: what the sidebar shows
/// for a reading that failed, and for how long.
struct LastPanesTests {
    // MARK: Internal

    @Test
    func `a reading that failed shows the sessions herdr last named`() {
        let held = LastPanes()
        held.remember([Self.pane("agentide--r--b--claude")])

        // The reading failed, so nothing at all is known about what
        // is running: taking that as an empty listing emptied every
        // session in the app at once.
        #expect(held.kept().map(\.sessionName) == ["agentide--r--b--claude"])
    }

    @Test
    func `failures outlasting the hold let the empty answer through`() {
        let held = LastPanes()
        let answered = Date()
        held.remember([Self.pane("agentide--r--b--claude")], at: answered)

        #expect(held.kept(now: answered.addingTimeInterval(119)).isEmpty == false)
        // A herdr that really has gone must stop being painted as
        // running.
        #expect(held.kept(now: answered.addingTimeInterval(121)).isEmpty)
    }

    @Test
    func `an empty answer that was read is remembered as one`() {
        let held = LastPanes()
        held.remember([Self.pane("agentide--r--b--claude")])
        held.remember([])

        // Nothing running is a fact when the reading itself worked.
        #expect(held.kept().isEmpty)
    }

    @Test
    func `nothing is held before herdr has answered once`() {
        #expect(LastPanes().kept().isEmpty)
    }

    // MARK: Private

    private static func pane(_ sessionName: String) -> HerdrPane {
        HerdrPane(
            sessionName: sessionName,
            paneID: "w1:p1",
            isFinished: false,
            activity: nil,
            foregroundCommand: nil,
            currentPath: "/tmp",
        )
    }
}
