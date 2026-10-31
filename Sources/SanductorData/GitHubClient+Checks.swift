import Foundation
import SanductorDomain

/// What a pull request's checks add up to. Split from the client
/// body for length.
extension GitHubClient {
    /// One pull request's full summary, including workflow and event names.
    public func pullRequestSummary(
        repositoryPath: String,
        number: Int,
        cachedChecks: [PullRequestCheck] = [],
        requiredChecks: RequiredChecksReader = { _ in nil },
    ) async throws -> PullRequestSummary? {
        let fields = Self.coreFields + "," + Self.statusFields + ",headRepository"
        let result = try await gh(["pr", "view", String(number), "--json", fields], in: repositoryPath)
        var summary = await Self.summaries(
            fromJSON: "[" + result.standardOutput + "]", requiredChecks: requiredChecks,
        )
        .first
        if var checks = summary?.checkDetails {
            let known = Dictionary(cachedChecks.map { ($0.id, $0) }) { first, _ in first }
            for index in checks.indices {
                if let cached = known[checks[index].id] {
                    checks[index].workflowName = cached.workflowName ?? checks[index].workflowName
                    checks[index].event = cached.event
                }
            }
            if checks.contains(where: { $0.jobID != nil && ($0.workflowName == nil || $0.event == nil) }),
               let names = try? await gh(
                   ["pr", "checks", String(number), "--json", "name,link,workflow,event"],
                   in: repositoryPath,
                   allowFailure: true,
               ),
               let workflows = try? JSONDecoder().decode([CheckWorkflow].self, from: Data(names.standardOutput.utf8))
            {
                for index in checks.indices {
                    if let workflow = workflows.first(where: { item in
                        item.name == checks[index].name && item.link == checks[index].link
                    }) {
                        checks[index].workflowName = workflow.workflow
                        checks[index].event = workflow.event
                    }
                }
            }
            summary?.checkDetails = checks
        }
        return summary
    }

    /// The rollup, the failures it counts and the failures it does
    /// not.
    struct Rollup {
        let checks: String
        let failingLinks: [String]
        let optionalFailures: Int
    }

    /// The rollup over the checks that decide it. With required
    /// checks named, only those count: a failing check nobody
    /// requires leaves the rollup green and is neither opened nor
    /// copied, only counted for the help, and a required one GitHub
    /// has yet to hear from keeps it pending, which is what GitHub's
    /// own merge box says. Without any, every check counts.
    static func rollup(_ rows: [CheckRow], required: Set<String>) -> Rollup {
        let counted = required.isEmpty ? rows : rows.filter { required.contains($0.name ?? $0.context ?? "") }
        let unreported = required.subtracting(counted.compactMap { $0.name ?? $0.context })
        let states = counted.map(Self.state) + Array(repeating: "PENDING", count: unreported.count)
        let failing = counted.filter { Self.isFailure(Self.state($0)) }
        return Rollup(
            checks: Self.aggregate(states),
            failingLinks: failing.compactMap(\.detailsUrl), // swiftformat:disable:this acronyms
            optionalFailures: rows.count { Self.isFailure(Self.state($0)) } - failing.count,
        )
    }

    static func autofixCheck(_ row: CheckRow, head: String = "") -> AutofixCheck {
        let link = row.detailsUrl ?? row.targetUrl ?? "" // swiftformat:disable:this acronyms
        let parts = GitHubRemote.fullName(ofURL: link) == nil ? [] : URL(string: link)?.pathComponents ?? []
        let run = parts.firstIndex(of: "runs").flatMap { index in
            parts.indices.contains(index + 1) ? parts[index + 1] : nil
        }
        let conclusion = (row.conclusion ?? row.state ?? "").uppercased()
        let status = row.status ?? (row.context != nil && ["SUCCESS", "FAILURE", "ERROR"].contains(conclusion)
            ? "COMPLETED" : "")
        return AutofixCheck(
            name: row.name ?? row.context ?? "",
            status: status,
            conclusion: conclusion,
            runID: (parts.dropLast().last == "job" ? parts.last : nil).map { "job:" + $0 }
                ?? run.map { "run:" + $0 } ?? row.createdAt.map { "status:" + (row.context ?? "") + ":" + $0 }
                ?? [
                    "check", head, row.name ?? row.context ?? "", link,
                    (row.startedAt ?? row.completedAt)?.ISO8601Format() ?? "",
                ].joined(separator: ":"),
            link: link,
        )
    }

    static func checkDetails(
        _ rows: [CheckRow],
        // swiftlint:disable:next discouraged_optional_collection - Unknown rules are distinct from no requirements.
        required: Set<String>?,
    ) -> [PullRequestCheck] {
        let checks = rows.map { row in
            let check = Self.autofixCheck(row)
            return PullRequestCheck(
                name: check.name,
                status: check.status.isEmpty ? "PENDING" : check.status,
                conclusion: check.conclusion,
                requirement: required.map { $0.contains(check.name) ? .required : .optional } ?? .unknown,
                link: check.link,
                startedAt: row.startedAt,
                completedAt: row.completedAt,
                workflowName: row.workflowName,
            )
        }
        let missing = (required ?? []).subtracting(checks.map(\.name)).sorted().map { name in
            PullRequestCheck(name: name, status: "EXPECTED", conclusion: "", requirement: .required)
        }
        return (checks + missing).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func state(_ row: CheckRow) -> String {
        (row.conclusion ?? row.state ?? "").uppercased()
    }

    private struct CheckWorkflow: Decodable {
        let name: String
        let link: String
        let workflow: String?
        let event: String?
    }

    /// A check run fails with `FAILURE`, a status context with
    /// `ERROR` too: one predicate, so what turns the rollup red is
    /// what is offered to open and what is counted.
    private static func isFailure(_ state: String) -> Bool {
        state == "FAILURE" || state == "ERROR"
    }

    private static func aggregate(_ states: [String]) -> String {
        guard states.isEmpty == false else {
            return ""
        }

        if states.contains(where: isFailure) {
            return "FAILURE"
        }
        if states.allSatisfy({ $0 == "SUCCESS" || $0 == "NEUTRAL" || $0 == "SKIPPED" }) {
            return "SUCCESS"
        }
        return "PENDING"
    }
}
