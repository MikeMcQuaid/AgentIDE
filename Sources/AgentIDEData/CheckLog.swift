import Foundation

/// Shared CI log formatting for Checks, Copy all and automatic fix prompts.
public enum CheckLog {
    // MARK: Public

    /// How many lines of each run's failed-step log are kept, and
    /// from which end. The tail is where the failure is: the
    /// assertion, the exit code, the last thing printed. The head is
    /// what was run and in what environment, which the tail rarely
    /// repeats and a fix needs to reproduce it. Whole logs run to
    /// megabytes; two hundred lines a run keeps a pull request with
    /// several failing runs pasteable into a prompt, and the middle
    /// is progress that neither end needs. Each end is bounded in
    /// bytes as well, since one line of minified output or a dumped
    /// blob can cost more than the other hundred and ninety-nine:
    /// whole lines go first from the far side of the end, and a line
    /// larger than the budget on its own is cut to it.
    public static let logHeadLines = 40
    /// The final lines retained alongside errors and their context.
    public static let logTailLines = 160

    /// Formats captured log text, retaining every failure even outside the head and tail.
    public static func format(log: String, heading: String, complete: Bool = false) -> String {
        let sections = condensed(log: log, complete: complete)
        let headed = sections.filter { $0.heading.isEmpty == false }
        if headed.count == 1, headed.count == sections.count, let only = sections.first {
            return "## " + heading + " · " + only.heading + "\n" + only.lines.joined(separator: "\n")
        }
        let body = sections.map { section in
            let title = section.heading.isEmpty ? "" : "### " + section.heading + "\n"
            return title + section.lines.joined(separator: "\n")
        }
        return "## " + heading + "\n" + body.joined(separator: "\n")
    }

    // MARK: Internal

    /// One log line, its job and step heading and its text.
    typealias LogLine = (heading: String, text: String)

    /// One job and step's lines, the pair named once above them.
    struct LogSection: Equatable {
        var heading: String
        var lines: [String]
    }

    static let logHeadBytes = 4_096
    static let logTailBytes = 16_384

    /// The lines kept either side of a kept line, what a diff shows.
    static let logContextLines = 3

    /// `gh run view --log-failed` prints `job<tab>step<tab>timestamp
    /// text`, the job and step on every line and the timestamp
    /// saying nothing a fix needs; this keeps the last lines, names
    /// each job and step once and strips timestamps, byte order
    /// marks and colour codes.
    static func condensed(log: String, complete: Bool = false) -> [LogSection] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
            .map { raw -> LogLine in
                let parts = raw.split(separator: "\t", maxSplits: Self.logColumns - 1, omittingEmptySubsequences: false)
                let tabbed = parts.count == Self.logColumns
                let heading = tabbed ? String(parts[0]) + " · " + String(parts[1]) : ""
                return (heading, Self.stripped(tabbed ? String(parts.last ?? "") : String(raw)))
            }
        // The first lines are the head and the rest is the tail,
        // each within its own budget, so a short log with one giant
        // line still keeps what was run as well as how it ended.
        let head = Self.capped(Array(lines.prefix(logHeadLines)), toBytes: logHeadBytes, keepingEnd: false)
        let tail = Self.capped(
            Array(lines.dropFirst(logHeadLines).suffix(logTailLines)),
            toBytes: logTailBytes,
            keepingEnd: true,
        )
        // The verdict of a long run is often in neither end: a
        // periphery warning or a failed test's own line sits in the
        // middle, and cutting it left both ends saying only that
        // something failed.
        let middle = Array(lines[head.count ..< (lines.count - tail.count)])
        let kept = complete ? lines : head + Self.verdicts(in: middle) + tail
        var sections = [LogSection]()
        for line in kept {
            if let last = sections.indices.last, sections[last].heading == line.heading {
                sections[last].lines.append(line.text)
            } else {
                sections.append(LogSection(heading: line.heading, lines: [line.text]))
            }
        }
        return sections
    }

    /// The lines that fit a byte budget, kept from one end: whole
    /// lines are dropped from the other end first, and a single line
    /// larger than the budget on its own is cut to it, an ellipsis
    /// where the cut was.
    static func capped(_ lines: [LogLine], toBytes budget: Int, keepingEnd: Bool) -> [LogLine] {
        var fitted = [LogLine]()
        var used = 0
        for line in keepingEnd ? lines.reversed() : lines {
            let bytes = line.text.utf8.count + 1
            guard used + bytes <= budget else {
                if fitted.isEmpty {
                    let room = max(budget - Self.ellipsis.utf8.count, 0)
                    let cut = keepingEnd
                        ? Self.ellipsis + Self.utf8Cut(line.text, bytes: room, fromEnd: true)
                        : Self.utf8Cut(line.text, bytes: room, fromEnd: false) + Self.ellipsis
                    fitted.append((line.heading, cut))
                }
                break
            }

            used += bytes
            fitted.append(line)
        }
        return keepingEnd ? fitted.reversed() : fitted
    }

    /// The lines of the cut middle worth keeping, what was cut
    /// between them counted in their place: every line naming an
    /// error or a failure, each with the lines either side a diff
    /// shows, whatever the budget, since those are the point of the
    /// copy; then lines naming a warning, the last first, while the
    /// tail's budget allows, since a build can print thousands.
    static func verdicts(in middle: [LogLine]) -> [LogLine] {
        var keep = Set<Int>()
        func context(of index: Int) -> ClosedRange<Int> {
            max(0, index - logContextLines) ... min(middle.count - 1, index + logContextLines)
        }
        for (index, line) in middle.enumerated() where Self.names(Self.failurePattern, line.text) {
            keep.formUnion(context(of: index))
        }
        var budget = logTailBytes
        for (index, line) in middle.enumerated().reversed()
            where Self.names(Self.warningPattern, line.text) && keep.contains(index) == false
        {
            let cost = context(of: index)
                .filter { keep.contains($0) == false }
                .reduce(0) { $0 + middle[$1].text.utf8.count + 1 }
            guard cost <= budget else {
                continue
            }

            budget -= cost
            keep.formUnion(context(of: index))
        }
        var verdicts = [LogLine]()
        var cut = 0
        for (index, line) in middle.enumerated() {
            guard keep.contains(index) else {
                cut += 1
                continue
            }

            if cut > 0 {
                verdicts.append(("", "[" + String(cut) + " lines cut]"))
                cut = 0
            }
            verdicts.append(line)
        }
        if cut > 0 {
            verdicts.append(("", "[" + String(cut) + " lines cut]"))
        }
        return verdicts
    }

    /// A log line without its timestamp, byte order mark or colour.
    static func stripped(_ text: String) -> String {
        text
            .replacing(/^\x{FEFF}?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/, with: "")
            .replacing(/\e\[[0-9;?]*[@-~]/, with: "")
    }

    // MARK: Private

    /// Job, step and text: the columns `gh` tabs apart.
    private static let logColumns = 3

    private static let failurePattern = "error|fail"
    private static let warningPattern = "warning"

    /// Where a line was cut.
    private static let ellipsis = "\u{2026}"

    private static func names(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// At most so many bytes of a line from one end, backed off to
    /// a character boundary so the cut never lands inside one.
    private static func utf8Cut(_ text: String, bytes: Int, fromEnd: Bool) -> String {
        var room = bytes
        while room > 0 {
            let slice = fromEnd ? text.utf8.suffix(room) : text.utf8.prefix(room)
            if let cut = String(bytes: slice, encoding: .utf8) {
                return cut
            }
            room -= 1
        }
        return ""
    }
}
