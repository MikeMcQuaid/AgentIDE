import Foundation
@testable import ReviewFeature
import Testing

/// Line numbers by binary search over where the lines start, which
/// is what keeps the ruler's draw off the whole document.
struct LineIndexTests {
    @Test
    func `every line terminator starts a line, and the number is found without a walk`() {
        // swiftlint:disable:next legacy_objc_type
        let starts = LineIndex.starts(in: "a\nbb\r\nc" as NSString)
        #expect(starts == [0, 2, 6])
        #expect(LineIndex.line(at: 0, starts: starts) == 1)
        #expect(LineIndex.line(at: 1, starts: starts) == 1)
        #expect(LineIndex.line(at: 2, starts: starts) == 2)
        #expect(LineIndex.line(at: 5, starts: starts) == 2)
        #expect(LineIndex.line(at: 6, starts: starts) == 3)
        #expect(LineIndex.line(at: 7, starts: starts) == 3)
    }

    @Test
    func `a final newline opens an empty line the text view draws, and nothing has one line`() {
        // swiftlint:disable:next legacy_objc_type
        let trailing = LineIndex.starts(in: "a\n" as NSString)
        #expect(trailing == [0, 2])
        #expect(LineIndex.line(at: 2, starts: trailing) == 2)
        // swiftlint:disable:next legacy_objc_type
        let empty = LineIndex.starts(in: "" as NSString)
        #expect(empty == [0])
        #expect(LineIndex.line(at: 0, starts: empty) == 1)
    }
}
