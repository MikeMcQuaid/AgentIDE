// MARK: - DiffSelection

/// A selected line within a parsed diff, addressed by hunk and line
/// index.
public struct DiffSelection: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a selection.
    public init(hunkIndex: Int, lineIndex: Int) {
        self.hunkIndex = hunkIndex
        self.lineIndex = lineIndex
    }

    // MARK: Public

    // These form the value's identity for Set membership; periphery's
    // assign-only check does not see synthesised Hashable use.
    // periphery:ignore
    public let hunkIndex: Int
    // periphery:ignore
    public let lineIndex: Int
}

// MARK: - PatchBuilder

/// Builds the minimal patch that, applied with `git apply -R --index`,
/// undoes only the selected lines of a commit, using the same
/// partial-hunk rules as `git add --patch`: unselected additions become
/// context, unselected deletions are dropped.
public enum PatchBuilder {
    // MARK: Public

    /// Builds the patch text for the selected lines, or nil when the
    /// selection contains no changes.
    public static func reversePatch(file: DiffFile, selection: Set<DiffSelection>) -> String? {
        let hunkTexts = file.hunks.enumerated().compactMap { hunkIndex, hunk in
            hunkText(hunk: hunk, hunkIndex: hunkIndex, selection: selection)
        }
        guard hunkTexts.isEmpty == false else {
            return nil
        }

        let header = "diff --git a/\(file.path) b/\(file.path)\n--- a/\(file.path)\n+++ b/\(file.path)\n"
        return header + hunkTexts.joined()
    }

    // MARK: Private

    private static func hunkText(hunk: DiffHunk, hunkIndex: Int, selection: Set<DiffSelection>) -> String? {
        var body = [String]()
        var oldCount = 0
        var newCount = 0
        var selectedChanges = 0

        for (lineIndex, line) in hunk.lines.enumerated() {
            let selected = selection.contains(DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex))
            switch (line.kind, selected) {
            case (.context, _):
                body.append(" " + line.content)
                oldCount += 1
                newCount += 1

            case (.addition, true):
                body.append("+" + line.content)
                newCount += 1
                selectedChanges += 1

            case (.addition, false):
                body.append(" " + line.content)
                oldCount += 1
                newCount += 1

            case (.deletion, true):
                body.append("-" + line.content)
                oldCount += 1
                selectedChanges += 1

            case (.deletion, false):
                break
            }
        }

        guard selectedChanges > 0 else {
            return nil
        }

        let header = "@@ -\(hunk.newStart),\(oldCount) +\(hunk.newStart),\(newCount) @@\n"
        return header + body.joined(separator: "\n") + "\n"
    }
}
