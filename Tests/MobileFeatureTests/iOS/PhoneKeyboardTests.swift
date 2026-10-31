#if os(iOS)
    @testable import MobileFeature
    import Testing
    import UIKit

    struct PhoneKeyboardTests {
        @Test(arguments: [false, true])
        func `keyboard reserves its height before UIKit presents it`(expanded: Bool) {
            let terminal = PhoneTerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            let keyboard = PhoneKeyboard(terminal: terminal, expanded: expanded)
            #expect(keyboard.frame.height == keyboard.intrinsicContentSize.height)
            #expect(keyboard.frame.height > 0)
        }
    }
#endif
