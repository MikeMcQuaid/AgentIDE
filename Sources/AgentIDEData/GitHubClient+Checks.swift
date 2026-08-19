import Foundation

/// What failed in CI, in the form an agent can be handed: the failing
/// steps of the failing job, rather than a link to go and read.
public extension GitHubClient {
    /// The pull request's failing checks, one line each, followed by
    /// each failing Actions run's failed step output; the links
    /// alone were useless for pasting into an agent. Passing,
    /// pending and skipped rows are noise for every caller.
    func failingChecks(repositoryPath: String, number: Int) async -> String {
        let checks = try? await gh(
            ["pr", "checks", String(number)],
            in: repositoryPath,
            allowFailure: true,
        )
        let failing = (checks?.standardOutput ?? "")
            .split(separator: "\n")
            .filter { line in
                let fields = line.split(separator: "\t")
                return fields.count > 1 && fields[1].localizedCaseInsensitiveContains("fail")
            }
            .map(String.init)
        var sections = failing.joined(separator: "\n")
        for job in Self.jobIDs(fromCheckLines: failing) {
            let excerpt = await failedSteps(ofJob: job, repositoryPath: repositoryPath)
            guard excerpt.isEmpty == false else {
                continue
            }

            sections += "\n\nFailed steps of job " + job + ":\n" + excerpt
        }
        return sections
    }

    /// One job's failed steps. `gh run view --job` narrows the log to
    /// the job that actually failed rather than every job in the run,
    /// which is what a failing check names; it refuses while the run
    /// is still going, and the API serves that job's log regardless,
    /// so the two are tried in turn.
    func failedSteps(ofJob job: String, repositoryPath: String) async -> String {
        let failed = try? await gh(
            ["run", "view", "--job", job, "--log-failed"],
            in: repositoryPath,
            allowFailure: true,
        )
        let output = (failed?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty == false {
            return Self.failureExcerpt(fromRunLog: output)
        }

        let live = try? await gh(
            ["api", "repos/{owner}/{repo}/actions/jobs/" + job + "/logs"],
            in: repositoryPath,
            allowFailure: true,
        )
        let raw = (live?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else {
            return ""
        }

        // The API serves the job's whole log without the step prefix
        // `gh` adds, so there is nothing to group by: the tail from
        // its first error is the failure.
        return Self.tail(of: raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            .prefixWithinLimit(Self.runLogLimit)
    }

    // MARK: Internal

    /// Enough log to diagnose without flooding the clipboard.
    internal static var runLogLimit: Int {
        // swiftlint:disable:next no_magic_numbers
        20_000
    }

    /// `gh run view --log-failed` prefixes every line with its job
    /// and step names, tab separated.
    internal static var stepPrefixFields: Int {
        // swiftlint:disable:next no_magic_numbers
        2
    }

    /// How many lines of a failed step to keep, and how many before
    /// its first error line for context.
    internal static var stepTailLines: Int {
        // swiftlint:disable:next no_magic_numbers
        60
    }

    internal static var errorContextLines: Int {
        // swiftlint:disable:next no_magic_numbers
        5
    }

    /// The useful part of a `gh run view --log-failed` dump: its
    /// lines carry a repeated `job\tstep\t` prefix, and the failure
    /// is at the end, so the head of a long log was setup noise
    /// rather than the error. Each failed step keeps its own tail,
    /// from its first error line where one exists.
    internal static func failureExcerpt(fromRunLog log: String) -> String {
        var steps = [String]()
        var lines = [String: [String]]()
        for raw in log.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = raw.split(separator: "\t", maxSplits: stepPrefixFields, omittingEmptySubsequences: false)
            let step = fields.count > stepPrefixFields
                ? fields[0 ..< stepPrefixFields].joined(separator: " / ")
                : ""
            let text = fields.count > stepPrefixFields ? String(fields[stepPrefixFields]) : String(raw)
            if lines[step] == nil {
                steps.append(step)
                lines[step] = []
            }
            lines[step]?.append(text)
        }
        return steps
            .map { step in
                let body = Self.tail(of: lines[step] ?? [])
                return step.isEmpty ? body : step + "\n" + body
            }
            .joined(separator: "\n\n")
            .prefixWithinLimit(runLogLimit)
    }

    /// One step's last lines, starting at its first error line when
    /// it has one: the message that explains the failure sits there,
    /// with the lines after it as context.
    internal static func tail(of lines: [String]) -> String {
        let markers = ["error:", "##[error]", "error ", "failed", "fatal:", "assertion"]
        let firstError = lines.firstIndex { line in
            let lowered = line.lowercased()
            return markers.contains { lowered.contains($0) }
        }
        let start = firstError.map { max($0 - errorContextLines, 0) }
            ?? max(lines.count - stepTailLines, 0)
        return lines[start...].suffix(stepTailLines).joined(separator: "\n")
    }

    /// Distinct Actions job ids from the failing check lines' links,
    /// in order. A failing check links its own job, which is the one
    /// worth reading: a run of fifty jobs where one failed otherwise
    /// pastes the other forty-nine as well. External checks without
    /// an Actions link contribute no logs.
    internal static func jobIDs(fromCheckLines lines: [String]) -> [String] {
        var ids = [String]()
        for line in lines {
            guard let range = line.range(of: "/job/") else {
                continue
            }

            let id = String(line[range.upperBound...].prefix(while: \.isNumber))
            if id.isEmpty == false, ids.contains(id) == false {
                ids.append(id)
            }
        }
        return ids
    }
}
