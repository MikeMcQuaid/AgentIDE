import Foundation

// NSTextView ranges are UTF-16 offsets, so NSString is the correct
// arithmetic here, not String.
// swiftlint:disable legacy_objc_type

/// Where each line of a document starts, so a line number is a
/// binary search rather than a walk from the top. The ruler asks on
/// every scroll, and walking to line four thousand on every frame
/// is what made a long file scroll in steps.
nonisolated enum LineIndex {
    // MARK: Internal

    /// The offset each line starts at, the first always zero; the
    /// empty line after a final newline counts, as the text view
    /// draws it.
    static func starts(in text: NSString) -> [Int] {
        var starts = [0]
        var index = 0
        let length = text.length
        while index < length {
            var end = 0
            var contentsEnd = 0
            let here = NSRange(location: index, length: 0)
            unsafe text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: here)
            // A line without a terminator is the last one.
            guard end > contentsEnd else {
                break
            }

            index = end
            starts.append(index)
        }
        return starts
    }

    /// The one-based line holding an offset.
    static func line(at location: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / Self.halves
            if starts[middle] <= location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return max(low, 1)
    }

    // MARK: Private

    /// The search halves its range each step.
    private static let halves = 2
}

// swiftlint:enable legacy_objc_type
