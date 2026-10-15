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

    /// Maximum formatted bytes per job, including an omission notice.
    public static let logByteLimit = 65_536

    /// Condenses complete logs before bounding unusually large diagnostics.
    public static func format(log: String, heading: String, byteLimit: Int = logByteLimit) -> String {
        let sections = condensed(log: log)
        var output = formatted(sections: sections, heading: heading)
        guard output.utf8.count > byteLimit else {
            return output
        }

        let notice = "\n[CI log shortened to fit the feedback budget; some diagnostics omitted]\n"
        let room = max(0, byteLimit - notice.utf8.count)
        let failureSections = failures(in: sections, includingContext: true)
        if failureSections.isEmpty == false {
            output = formatted(sections: failureSections, heading: heading)
            if output.utf8.count > room {
                output = formatted(sections: failures(in: sections, includingContext: false), heading: heading)
            }
        }
        if output.utf8.count <= room {
            return output + notice
        }
        // swiftlint:disable:next no_magic_numbers - Divide the space equally between both ends.
        let headRoom = room / 2
        return utf8Cut(output, bytes: headRoom, fromEnd: false)
            + utf8Cut(notice, bytes: min(byteLimit, notice.utf8.count), fromEnd: false)
            + utf8Cut(output, bytes: room - headRoom, fromEnd: true)
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
    static func condensed(log: String) -> [LogSection] {
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
        let kept = head + Self.verdicts(in: middle) + tail
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
    /// error or a failure, each with surrounding diagnostic context,
    /// whatever the budget, since those are the point of the
    /// copy; then lines naming a warning, the last first, while the
    /// tail's budget allows, since a build can print thousands.
    static func verdicts(in middle: [LogLine]) -> [LogLine] {
        var keep = Set<Int>()
        for (index, line) in middle.enumerated() where Self.names(Self.failurePattern, line.text) {
            keep.formUnion(Self.context(of: index, in: middle))
        }
        var budget = logTailBytes
        for (index, line) in middle.enumerated().reversed()
            where Self.names(Self.warningPattern, line.text) && keep.contains(index) == false
        {
            guard line.text.utf8.count + 1 <= budget else {
                continue
            }

            for candidate in Self.context(of: index, in: middle).sorted(by: { abs($0 - index) < abs($1 - index) })
                where keep.contains(candidate) == false
            {
                let cost = middle[candidate].text.utf8.count + 1
                guard cost <= budget else {
                    continue
                }

                budget -= cost
                keep.insert(candidate)
            }
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

    private static let failurePattern = #"\b(?:err(?:or)?s?|fail(?:s|ed|ing|ures?)?|fatal|critical|panic(?:ked)?)\b"#
        + #"|(?-i:\b(?:[A-Z][A-Za-z0-9]*)?(?:Error|Exception))(?::|$)|[❌✘✖]"#
    private static let warningPattern = #"\bwarn(?:ing)?s?\b|(?-i:\b[A-Z][A-Za-z0-9]*Warning):|⚠"#
    private static let contextPattern = #"^(?:\s|$|Traceback\b|Caused by:|Suppressed:|stack (?:trace|backtrace):"#
        + #"|goroutine \d+ \[[^\]\r\n]+\]:$|[\w./-]+\.(?:\(\*?\w+\)\.)?[\w.]+\([^()\r\n]*\)$"#
        + #"|\d+\s*\||[~^+-]|@@)"#
    private static let diagnosticContextLines = 40

    /// Where a line was cut.
    private static let ellipsis = "\u{2026}"

    private static func formatted(sections: [LogSection], heading: String) -> String {
        if sections.count == 1, let only = sections.first, only.heading.isEmpty == false {
            return "## " + heading + " · " + only.heading + "\n" + only.lines.joined(separator: "\n")
        }
        let body = sections.map { section in
            let title = section.heading.isEmpty ? "" : "### " + section.heading + "\n"
            return title + section.lines.joined(separator: "\n")
        }
        return "## " + heading + "\n" + body.joined(separator: "\n")
    }

    private static func failures(in sections: [LogSection], includingContext: Bool) -> [LogSection] {
        sections.compactMap { section in
            let lines = section.lines.map { (heading: section.heading, text: $0) }
            let indices = lines.indices.filter { Self.names(Self.failurePattern, lines[$0].text) }
            guard indices.isEmpty == false else {
                return nil
            }

            let kept = includingContext ? Set(indices.flatMap { Self.context(of: $0, in: lines) }).sorted() : indices
            return LogSection(heading: section.heading, lines: kept.map { lines[$0].text })
        }
    }

    private static func context(of index: Int, in lines: [LogLine]) -> ClosedRange<Int> {
        func bound(towards direction: Int) -> Int {
            var result = index
            var continues = true
            for distance in 1 ... diagnosticContextLines {
                let next = index + distance * direction
                guard lines.indices.contains(next), lines[next].heading == lines[index].heading else {
                    break
                }

                continues = continues && Self.names(Self.contextPattern, lines[next].text)
                guard distance <= logContextLines || continues else {
                    break
                }

                result = next
            }
            return result
        }
        return bound(towards: -1) ... bound(towards: 1)
    }

    private static func names(_ pattern: String, _ text: String) -> Bool {
        // swiftlint:disable:next legacy_objc_type - ICU matches emoji scalars with presentation selectors.
        (text as NSString).range(of: pattern, options: [.regularExpression, .caseInsensitive]).location != NSNotFound
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
