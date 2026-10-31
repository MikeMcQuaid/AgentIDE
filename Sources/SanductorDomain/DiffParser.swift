/// Parses `git diff` unified output into files, hunks and lines.
public enum DiffParser {
    // MARK: Public

    /// Parses unified diff text; unrecognised lines are ignored.
    public static func parse(_ diff: String) -> [DiffFile] {
        var files = [DiffFile]()
        var paths = Paths()
        var hunks = [DiffHunk]()
        var lines = [DiffLine]()
        var starts: (old: Int, new: Int) = (0, 0)
        var inHunk = false

        func closeHunk() {
            guard inHunk else {
                return
            }

            hunks.append(DiffHunk(oldStart: starts.old, newStart: starts.new, lines: lines))
            lines = []
            inHunk = false
        }

        func closeFile() {
            closeHunk()
            // Prefer the new path; fall back to the old path so deleted
            // files (whose new path is /dev/null) are still represented.
            if let path = paths.new ?? paths.old {
                // `--- /dev/null` (a git-added file) and the synthetic
                // untracked diff both leave the old path empty.
                files.append(DiffFile(
                    path: path, hunks: hunks, isNew: paths.sawOld && paths.old == nil, oldPath: paths.renamedFrom,
                ))
            }
            paths = Paths()
            hunks = []
        }

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                closeFile()
            } else if line.hasPrefix("@@ ") {
                closeHunk()
                starts = hunkStarts(line)
                inHunk = true
            } else if inHunk {
                if let parsed = diffLine(line) {
                    lines.append(parsed)
                }
            } else {
                paths.consume(line)
            }
        }
        closeFile()
        return files
    }

    // MARK: Private

    /// The `-old` and `+new` markers of a hunk header.
    private static let hunkMarkerCount = 2

    private static func hunkStarts(_ line: String) -> (old: Int, new: Int) {
        let numbers = line.split(separator: " ").dropFirst().prefix(hunkMarkerCount).map { marker in
            Int(marker.dropFirst().prefix(while: \.isNumber)) ?? 0
        }
        return (numbers.first ?? 0, numbers.last ?? 0)
    }

    private static func diffLine(_ line: String) -> DiffLine? {
        // git prefixes every hunk body line, blank ones included, with
        // a space; a truly empty line is the trailing newline after the
        // hunk, not a context line, so it ends the body.
        switch line.first {
        case "+":
            DiffLine(kind: .addition, content: String(line.dropFirst()))

        case "-":
            DiffLine(kind: .deletion, content: String(line.dropFirst()))

        case " ":
            DiffLine(kind: .context, content: String(line.dropFirst()))

        default:
            nil
        }
    }
}
