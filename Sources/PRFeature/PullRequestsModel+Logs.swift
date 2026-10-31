import AppKit
import SanductorData
import SanductorDomain

/// Copying the head and tail of every failing Actions run's log,
/// the raw material a fix prompt needs, condensed so no token is
/// spent on what `gh` repeats per line. Split from the actions for
/// length.
extension PullRequestsModel {
    func includesOptionalLogs(for summary: PullRequestSummary) -> Bool {
        _ = checkCopyGeneration
        return store.load().includeOptionalCheckLogs[AppMetadata.threadsKey(
            repositoryPath: repository.path, number: summary.number,
        )] ?? false
    }

    func setIncludesOptionalLogs(_ include: Bool, for summary: PullRequestSummary) {
        store.update { metadata in
            metadata.includeOptionalCheckLogs[AppMetadata.threadsKey(
                repositoryPath: repository.path, number: summary.number,
            )] = include
        }
        checkCopyGeneration += 1
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

    static func copyableFailingChecks(
        in summary: PullRequestSummary, includeOptional: Bool = false,
    ) -> [PullRequestCheck] {
        (summary.checkDetails ?? []).filter { check in
            check.canReadLog && (includeOptional
                ? ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED"]
                .contains(check.conclusion)
                : summary.failingCheckLinks.contains(check.link))
        }
    }

    /// Every failing run's condensed log under a heading naming the
    /// run and, when it has only one job and step, those too.
    func failingLogs(for summary: PullRequestSummary) async throws -> String {
        if summary.checkDetails != nil {
            var logs = [String]()
            var unreadable: any Error?
            for check in Self.copyableFailingChecks(in: summary, includeOptional: includesOptionalLogs(for: summary)) {
                guard let jobID = check.jobID else {
                    continue
                }

                do {
                    try await logs.append(CheckLog.format(log: fetchCheckLog(jobID), heading: check.name))
                } catch {
                    if check.conclusion != "CANCELLED" || error is GitHubClient.JobLogUnavailable == false {
                        unreadable = unreadable ?? error
                    }
                }
            }
            let selected = (summary.checkDetails ?? []).filter { check in
                includesOptionalLogs(for: summary) || summary.failingCheckLinks.contains(check.link)
            }
            if logs.isEmpty, unreadable == nil, selected.isEmpty == false,
               selected.allSatisfy({ check in
                   check.isComplete && ["CANCELLED", "SKIPPED", "SUCCESS", "NEUTRAL"].contains(check.conclusion)
               }),
               selected.contains(where: { ["CANCELLED", "SKIPPED"].contains($0.conclusion) })
            {
                return "Cancelled or skipped checks produced no logs."
            }
            guard logs.isEmpty == false else {
                throw unreadable ?? GitHubClient.RunLogsUnavailable(
                    failedJobs: summary.failingCheckLinks.count,
                    links: summary.failingCheckLinks,
                )
            }

            return logs.joined(separator: "\n\n")
        }
        var runs = [String]()
        var unreadable: any Error?
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

            runs.append(CheckLog.format(log: log, heading: "Run " + String(runID)))
        }
        guard runs.isEmpty == false else {
            throw unreadable ?? GitHubClient.RunLogsUnavailable(failedJobs: 0)
        }

        return runs.joined(separator: "\n\n")
    }

    /// Copies the failing logs to the clipboard; false opens the
    /// errors surface, and a pull request whose failing checks are
    /// not Actions runs has nothing to copy.
    func copyFailingLogs(_ summary: PullRequestSummary, pasteboard: NSPasteboard = .general) async -> Bool {
        pasteboard.clearContents()
        let links = includesOptionalLogs(for: summary)
            ? (summary.checkDetails ?? []).map(\.link) : summary.failingCheckLinks
        let runs = Self.runIDs(in: links)
        guard runs.isEmpty == false else {
            report("None of #" + String(summary.number) + "'s failing checks is an Actions run; open them instead.")
            return false
        }

        do {
            let text = try await failingLogs(for: summary)
            pasteboard.setString(text, forType: .string)
            note("Copied the available failing check logs from #" + String(summary.number) + ".")
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
