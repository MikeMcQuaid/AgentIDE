import AgentIDEDomain

extension LocalReviewInput {
    /// Keep the anchor and nearby lines from the exact diff the reviewer saw.
    static func context(file: DiffFile, line: Int?) -> String? {
        guard file.hunks.isEmpty == false else {
            return nil
        }

        let hunk = file.hunks[file.hunkIndex(containing: line) ?? 0]
        var number = hunk.newStart
        let anchor = hunk.lines.firstIndex { entry in
            defer {
                if entry.kind != .deletion {
                    number += 1
                }
            }
            return entry.kind != .deletion && number == line
        } ?? 0
        let start = max(0, anchor - contextRadius)
        let end = min(hunk.lines.count, anchor + contextRadius + 1)
        let preceding = hunk.lines.prefix(start)
        let excerpt = DiffHunk(
            oldStart: hunk.oldStart + preceding.count { $0.kind != .addition },
            newStart: hunk.newStart + preceding.count { $0.kind != .deletion },
            lines: Array(hunk.lines[start ..< end]),
        )
        return snapshot(files: [DiffFile(path: file.path, hunks: [excerpt])])
    }

    private static let contextRadius = 3
}
