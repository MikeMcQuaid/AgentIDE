import SwiftUI
@testable import TerminalUI
import Testing

/// Exercises the SGR conversion behind the scrollback viewer's
/// colours.
struct ANSITextTests {
    @Test
    func `colours split runs and resets clear them`() {
        let styled = ANSIText.attributed("\u{1B}[31mred\u{1B}[0m plain")
        let runs = Array(styled.runs)
        #expect(runs.count == 2)
        #expect(String(styled.characters) == "red plain")
        #expect(runs.first?.foregroundColor != nil)
        #expect(runs.last?.foregroundColor == nil)
    }

    @Test
    func `extended colours and truecolour parse`() {
        let indexed = ANSIText.attributed("\u{1B}[38;5;196mhot\u{1B}[0m")
        #expect(Array(indexed.runs).first?.foregroundColor != nil)

        let direct = ANSIText.attributed("\u{1B}[38;2;10;200;30mgreen\u{1B}[0m")
        #expect(Array(direct.runs).first?.foregroundColor != nil)

        let background = ANSIText.attributed("\u{1B}[48;5;28mdiff\u{1B}[49m")
        #expect(Array(background.runs).first?.backgroundColor != nil)
    }

    @Test
    func `unknown escapes are stripped and plain undoes styling`() {
        let mixed = "\u{1B}[2J\u{1B}]0;title\u{07}\u{1B}[1mbold\u{1B}[22m text"
        #expect(ANSIText.plain(mixed) == "bold text")
        let styled = ANSIText.attributed(mixed)
        #expect(String(styled.characters) == "bold text")
    }
}
