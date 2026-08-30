import AgentIDEDomain
import AppKit

/// Copying the tail of every failing Actions run's log, the raw
/// material a fix prompt needs, condensed so no token is spent on
/// what `gh` repeats per line. Split from the actions for length.
extension PullRequestsModel {
    /// How many lines of each run's failed-step log are kept: the
    /// end is where the failure is, and whole logs run to megabytes.
    static let logTailLines = 200

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
            .map { raw -> (heading: String, text: String) in
                let parts = raw.split(separator: "\t", maxSplits: Self.logColumns - 1, omittingEmptySubsequences: false)
                let tabbed = parts.count == Self.logColumns
                let heading = tabbed ? String(parts[0]) + " · " + String(parts[1]) : ""
                return (heading, Self.stripped(tabbed ? String(parts.last ?? "") : String(raw)))
            }
        var kept = Array(lines.suffix(logTailLines))
        if lines.count > logTailLines {
            kept.insert(("", "[" + String(lines.count - logTailLines) + " earlier lines cut]"), at: 0)
        }
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
        for runID in Self.runIDs(in: summary.failingCheckLinks) {
            let sections = try await Self.condensed(log: fetchFailedRunLog(runID))
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
        } catch {
            report("Reading the failing logs of #" + String(summary.number) + " failed: " + error.localizedDescription)
            return false
        }
    }
}
