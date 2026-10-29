@testable import MobileFeature
import Testing

struct MobileKeyActivationTests {
    @Test
    func `assistive activation sends one key without holding it`() {
        var holds = [Bool]()
        let activation = MobileKeyActivation { holds.append($0) }
        activation.activate()
        activation.activate()
        #expect(holds == [false, false])
    }

    @Test
    func `a physical tap sends immediately and its release never sends twice`() {
        var holds = [Bool]()
        let activation = MobileKeyActivation { holds.append($0) }
        activation.touchDown()
        #expect(holds == [true])
        activation.activate()
        #expect(holds == [true])
        activation.touchDown()
        activation.activate()
        activation.activate()
        #expect(holds == [true, true, false])
    }

    @Test
    func `a cancelled touch does not swallow the next assistive activation`() {
        var holds = [Bool]()
        let activation = MobileKeyActivation { holds.append($0) }
        activation.touchDown()
        activation.cancelTouch()
        activation.activate()
        #expect(holds == [true, false])
    }
}
