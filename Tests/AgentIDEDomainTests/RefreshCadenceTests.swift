@testable import AgentIDEDomain
import Foundation
import Testing

/// When the dashboard ticks, and when a tick may ask herdr.
struct RefreshCadenceTests {
    @Test
    func `the tick slows on battery and slower still out of sight`() {
        #expect(RefreshCadence.pollSeconds(setting: 5, visible: true, onBattery: false) == 5)
        // Settings' own slower choice is kept on battery.
        #expect(RefreshCadence.pollSeconds(setting: 90, visible: true, onBattery: true) == 90)
        #expect(RefreshCadence.pollSeconds(setting: 5, visible: true, onBattery: true) == 60)
        #expect(RefreshCadence.pollSeconds(setting: 5, visible: false, onBattery: false) == 60)
        #expect(RefreshCadence.pollSeconds(setting: 5, visible: false, onBattery: true) == 300)
    }

    @Test
    func `a tick asks herdr only once its safety interval has passed`() {
        let now = Date()
        #expect(RefreshCadence.panesDue(lastRead: nil, now: now, onBattery: false))
        #expect(RefreshCadence.panesDue(lastRead: now.addingTimeInterval(-30), now: now, onBattery: false) == false)
        #expect(RefreshCadence.panesDue(lastRead: now.addingTimeInterval(-61), now: now, onBattery: false))
        // On battery the same minute is not yet due.
        #expect(RefreshCadence.panesDue(lastRead: now.addingTimeInterval(-61), now: now, onBattery: true) == false)
        #expect(RefreshCadence.panesDue(lastRead: now.addingTimeInterval(-301), now: now, onBattery: true))
        #expect(RefreshCadence.paneLoadSeconds(onBattery: true) > RefreshCadence.paneLoadSeconds(onBattery: false))
    }

    @Test
    func `every safety interval slows by the one factor on battery`() {
        #expect(RefreshCadence.slowed(60, onBattery: false) == 60)
        #expect(RefreshCadence.slowed(60, onBattery: true) == 300)
    }
}
