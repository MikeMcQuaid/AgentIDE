@testable import MobileFeature
import Testing

struct MobileTerminalKeysTests {
    @Test(arguments: ["A", "B", "C", "D"])
    func `shift arrows retain direction and combine with control`(direction: String) {
        let arrow = Array(("\u{1B}[" + direction).utf8)
        #expect(
            MobileTerminalKeys.modified(arrow, shift: false, control: false) == arrow,
        )
        #expect(
            MobileTerminalKeys.modified(arrow, shift: true, control: false) == Array(("\u{1B}[1;2" + direction).utf8),
        )
        #expect(
            MobileTerminalKeys.modified(arrow, shift: false, control: true) == Array(("\u{1B}[1;5" + direction).utf8),
        )
        #expect(
            MobileTerminalKeys.modified(arrow, shift: true, control: true) == Array(("\u{1B}[1;6" + direction).utf8),
        )
    }

    @Test
    func `page and function keys keep their codes while tab reverses`() {
        #expect(
            MobileTerminalKeys.modified(Array("\u{1B}[5~".utf8), shift: true, control: false)
                == Array("\u{1B}[5;2~".utf8),
        )
        #expect(
            MobileTerminalKeys.modified(Array("\u{1B}[6~".utf8), shift: true, control: true)
                == Array("\u{1B}[6;6~".utf8),
        )
        #expect(
            MobileTerminalKeys.modified(Array("\u{1B}OP".utf8), shift: true, control: false)
                == Array("\u{1B}[1;2P".utf8),
        )
        #expect(
            MobileTerminalKeys.modified([9], shift: true, control: false) == Array("\u{1B}[Z".utf8),
        )
        #expect(
            MobileTerminalKeys.modified([27], shift: true, control: true) == [27],
        )
    }
}
