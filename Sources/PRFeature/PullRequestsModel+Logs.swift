import AgentIDEDomain
import AppKit

/// Copying the tail of every failing Actions run's log, the raw
/// material a fix prompt needs. Split from the actions for length.
extension PullRequestsModel {
    /// How many lines of each run's failed-step log are kept: the
    /// end is where the failure is, and whole logs run to megabytes.
    static let logTailLines = 200

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

    /// The last lines of a log, saying when it was cut.
    static func tail(of log: String) -> String {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > logTailLines else {
            return log
        }

        return "[" + String(lines.count - logTailLines) + " earlier lines cut]\n"
            + lines.suffix(logTailLines).joined(separator: "\n")
    }

    /// Every failing run's log tail under a heading naming the run.
    func failingLogs(for summary: PullRequestSummary) async throws -> String {
        var sections = [String]()
        for runID in Self.runIDs(in: summary.failingCheckLinks) {
            let log = try await fetchFailedRunLog(runID)
            sections.append("## Run " + String(runID) + "\n" + Self.tail(of: log))
        }
        return sections.joined(separator: "\n\n")
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
