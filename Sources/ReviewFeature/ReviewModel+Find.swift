import AgentIDEDomain

/// Finding text in the diff. The editor and the terminals answer
/// AppKit's own find bar, but a diff is a list of views rather than
/// one text view, so the review pane searches its files itself.
extension ReviewModel {
    /// Where a match is: the hunk holding it, which is what the list
    /// can scroll to.
    struct FindTarget: Hashable {
        let file: String
        let hunk: Int

        /// The identity the diff gives that hunk's view.
        var id: String {
            file + "#" + String(hunk)
        }
    }

    /// What the find bar reports beside its field.
    var findSummary: String {
        guard findQuery.isEmpty == false else {
            return ""
        }
        guard findTargets.isEmpty == false else {
            return "No matches"
        }

        return String(currentFind + 1) + " of " + String(findTargets.count)
    }

    /// The hunk the diff should be showing, nil when nothing matches.
    var currentFindTarget: String? {
        findTargets.indices.contains(currentFind) ? findTargets[currentFind].id : nil
    }

    /// Whether a line has anything to highlight, so the renderer
    /// only searches lines while a query is live.
    func findRanges(in line: String) -> [Range<String.Index>] {
        guard findQuery.isEmpty == false else {
            return []
        }

        var ranges = [Range<String.Index>]()
        var start = line.startIndex
        while let range = line.range(of: findQuery, options: .caseInsensitive, range: start ..< line.endIndex) {
            ranges.append(range)
            start = range.upperBound > range.lowerBound ? range.upperBound : line.index(after: range.lowerBound)
            guard start < line.endIndex else {
                break
            }
        }
        return ranges
    }

    /// Recounts the hunks holding a match, keeping the current one
    /// where it can: the query grows a character at a time, and the
    /// diff should not jump back to the top for each of them.
    func updateFindTargets() {
        let previous = currentFindTarget
        findTargets = findQuery.isEmpty ? [] : files.flatMap { file in
            file.hunks
                .indices
                .filter { index in
                    file.hunks[index].lines.contains { findRanges(in: $0.content).isEmpty == false }
                }
                .map { FindTarget(file: file.path, hunk: $0) }
        }
        currentFind = findTargets.firstIndex { $0.id == previous } ?? 0
    }

    /// Moves to the next or previous match, wrapping at both ends.
    func moveFind(by offset: Int) {
        guard findTargets.isEmpty == false else {
            return
        }

        currentFind = (currentFind + offset + findTargets.count) % findTargets.count
    }
}
