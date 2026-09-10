import AgentIDEData
import AgentIDEDomain
import AppKit

/// Copying the head and tail of every failing Actions run's log,
/// the raw material a fix prompt needs, condensed so no token is
/// spent on what `gh` repeats per line. Split from the actions for
/// length.
extension PullRequestsModel {
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
    static let logHeadLines = 40
    static let logTailLines = 160
    static let logHeadBytes = 4_096
    static let logTailBytes = 16_384

    /// One log line, its job and step heading and its text.
    typealias LogLine = (heading: String, text: String)

    /// Job, step and text: the columns `gh` tabs apart.
    private static let logColumns = 3

    /// One job and step's lines, the pair named once above them.
    struct LogSection: Equatable {
        var heading: String
        var lines: [String]
    }

    /// The Actions run ids among a pull request's failing checks,
    /// each once, in order; checks from elsewhere have no log here.
    static func runIDs(in links: [String]) -> [Int] {
        var seen = Set<Int>()
        return links.compactMap { link in
            guard let range = link.firstRange(of: "/actions/runs/") else {
                return nil
            }

            let digits = link[range.upperBound...].prefix(while: \.isNumber)
            return Int(digits)
        }
        .filter { seen.insert($0).inserted }
    }

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
        let cut = lines.count - head.count - tail.count
        let kept = head + (cut > 0 ? [("", "[" + String(cut) + " lines cut]")] : []) + tail
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

    /// Where a line was cut.
    private static let ellipsis = "\u{2026}"

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

    /// A log line without its timestamp, byte order mark or colour.
    static func stripped(_ text: String) -> String {
        text
            .replacing(/^\x{FEFF}?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/, with: "")
            .replacing(/\e\[[0-9;?]*[@-~]/, with: "")
    }

    /// Every failing run's condensed log under a heading naming the
    /// run and, when it has only one job and step, those too.
    func failingLogs(for summary: PullRequestSummary) async throws -> String {
        var runs = [String]()
        var unreadable: (any Error)?
        for runID in Self.runIDs(in: summary.failingCheckLinks) {
            // A run with nothing to give is skipped, not fatal: what
            // the other runs already have is what the prompt wants,
            // and only every run coming back empty is worth saying.
            let log: String
            do {
                log = try await fetchFailedRunLog(runID)
            } catch {
                unreadable = unreadable ?? error
                continue
            }

            let sections = Self.condensed(log: log)
            let headed = sections.filter { $0.heading.isEmpty == false }
            if headed.count == 1, headed.count == sections.count, let only = sections.first {
                let heading = "## Run " + String(runID) + " · " + only.heading
                runs.append(heading + "\n" + only.lines.joined(separator: "\n"))
            } else {
                let body = sections.map { section in
                    let heading = section.heading.isEmpty ? "" : "### " + section.heading + "\n"
                    return heading + section.lines.joined(separator: "\n")
                }
                runs.append("## Run " + String(runID) + "\n" + body.joined(separator: "\n"))
            }
        }
        guard runs.isEmpty == false else {
            throw unreadable ?? GitHubClient.RunLogsUnavailable(failedJobs: 0)
        }

        return runs.joined(separator: "\n\n")
    }

    /// Copies the failing logs to the clipboard; false opens the
    /// errors surface, and a pull request whose failing checks are
    /// not Actions runs has nothing to copy.
    func copyFailingLogs(_ summary: PullRequestSummary) async -> Bool {
        let runs = Self.runIDs(in: summary.failingCheckLinks)
        guard runs.isEmpty == false else {
            report("None of #" + String(summary.number) + "'s failing checks is an Actions run; open them instead.")
            return false
        }

        do {
            let text = try await failingLogs(for: summary)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            note("Copied the failing logs of " + String(runs.count) + " runs from #" + String(summary.number) + ".")
            return true
        } catch let error as GitHubClient.RunLogsUnavailable {
            // Only a run GitHub has yet to publish is a "yet".
            report("Nothing to copy from #" + String(summary.number) + " yet: " + error.localizedDescription)
            return false
        } catch {
            // Anything else (no network, no `gh` credentials) is said
            // as what it is: waiting will not cure it.
            report("Could not read #" + String(summary.number) + "'s failing logs: " + error.localizedDescription)
            return false
        }
    }
}
