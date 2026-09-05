@testable import AgentIDEDomain
import Testing

/// What Option and an arrow send to a program that reads plain
/// terminal input.
struct TerminalKeysTests {
    @Test
    func `option and a sideways arrow move a word the way readline does`() {
        // Meta-b and meta-f: what every shell binds, and what the
        // kitty encoding a shell cannot read replaced.
        #expect(TerminalKeys.optionArrow(.left, applicationCursor: false) == [0x1B, 0x62])
        #expect(TerminalKeys.optionArrow(.right, applicationCursor: false) == [0x1B, 0x66])
        // The cursor mode has nothing to say about these two.
        #expect(TerminalKeys.optionArrow(.left, applicationCursor: true) == [0x1B, 0x62])
    }

    @Test
    func `option and an upright arrow is meta and the plain key`() {
        #expect(TerminalKeys.optionArrow(.upward, applicationCursor: false) == [0x1B, 0x1B, 0x5B, 0x41])
        #expect(TerminalKeys.optionArrow(.downward, applicationCursor: false) == [0x1B, 0x1B, 0x5B, 0x42])
        // A program in application cursor mode asked for the other
        // form, and Option does not change which form it gets.
        #expect(TerminalKeys.optionArrow(.upward, applicationCursor: true) == [0x1B, 0x1B, 0x4F, 0x41])
    }
}
