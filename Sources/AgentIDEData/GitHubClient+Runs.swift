import Foundation

/// Actions runs, split from the client body for length.
extension GitHubClient {
    /// One job of a run; beside its listing rather than nested in
    /// it, since types nest at most one level deep. Internal for
    /// the parsing tests.
    struct RunJob: Decodable {
        let databaseId: Int // swiftformat:disable:this acronyms
        let name: String?
        let conclusion: String?

        // A job's own steps, which conclude before it does. Absent
        // rather than empty when the listing carried none, and a
        // non-optional would fail the whole decode.
        // swiftlint:disable:next discouraged_optional_collection
        let steps: [RunStep]?
    }

    /// One step of a job; only its conclusion matters here.
    struct RunStep: Decodable {
        let conclusion: String?
    }

    /// Why a run handed over no log, in the app's own words: gh's
    /// refusal names a run still in progress, which is neither what
    /// happened nor anything to act on.
    public struct RunLogsUnavailable: LocalizedError, Sendable {
        // MARK: Lifecycle

        /// Creates the refusal, naming how many jobs have failed.
        public init(failedJobs: Int) {
            self.failedJobs = failedJobs
        }

        // MARK: Public

        /// How many of the run's jobs have failed so far.
        public let failedJobs: Int

        public var errorDescription: String? {
            guard failedJobs > 0 else {
                return "no job in this run has failed yet, so there is nothing to copy."
            }

            let jobs = failedJobs == 1 ? "1 failed job" : String(failedJobs) + " failed jobs"
            return "GitHub has no logs for its " + jobs
                + " yet; each one appears as its job finishes."
        }
    }

    /// The failed steps' log of one Actions run, as `gh` prints it.
    /// A run still in progress has no whole-run log to give, but
    /// each job that already failed has its own, so those answer
    /// instead of failing while the rest of the run is still
    /// deciding; a job whose log nothing will hand over yet is
    /// skipped rather than fatal, and only a run with no failed log
    /// at all keeps the original refusal.
    public func failedRunLog(repositoryPath: String, runID: Int) async throws -> String {
        do {
            return try await gh(["run", "view", String(runID), "--log-failed"], in: repositoryPath).standardOutput
        } catch {
            let jobs = try await gh(["run", "view", String(runID), "--json", "jobs"], in: repositoryPath)
            let failed = Self.failedJobs(fromJSON: jobs.standardOutput)
            var logs = [String]()
            for job in failed {
                if let log = await jobLog(job, repositoryPath: repositoryPath) {
                    logs.append(log)
                }
            }
            guard logs.isEmpty == false else {
                // Never gh's own wording: it names a run still in
                // progress, when what matters is whether any failed
                // job has a log to give.
                throw RunLogsUnavailable(failedJobs: failed.count)
            }

            return logs.joined(separator: "\n")
        }
    }

    /// The jobs a `--json jobs` listing says failed, separated for
    /// tests.
    static func failedJobs(fromJSON json: String) -> [RunJob] {
        guard let data = json.data(using: .utf8),
              let run = try? JSONDecoder().decode(RunJobs.self, from: data)
        else {
            return []
        }

        return run.jobs.filter(Self.hasFailed)
    }

    // MARK: Private

    /// Whether a job has failed. Its own conclusion says so once it
    /// finishes, but a check goes red the moment a step fails and
    /// the job runs on: waiting for the conclusion is what left
    /// nothing to copy while a run was still going.
    private static func hasFailed(_ job: RunJob) -> Bool {
        let outcomes = [job.conclusion] + (job.steps ?? []).map(\.conclusion)
        return outcomes.contains { Self.failedConclusions.contains(($0 ?? "").uppercased()) }
    }

    /// Every conclusion worth reading a log for.
    private static let failedConclusions: Set<String> = ["FAILURE", "CANCELLED", "TIMED_OUT"]

    /// Whether an answer reads as the log text it should be: bytes
    /// that decode as nothing arrive as an empty string, and an
    /// archive that does decode is known by its own header.
    static func isText(_ output: String) -> Bool {
        output.isEmpty == false
            && output.hasPrefix("PK\u{3}\u{4}") == false
            && output.contains("\0") == false
    }

    /// The slice of `gh run view --json jobs` the fallback reads.
    private struct RunJobs: Decodable {
        let jobs: [RunJob]
    }

    /// One failed job's log while its run still goes: `gh run view
    /// --job` where gh allows it, else the REST job log, which has
    /// no in-progress gate for a job that has finished. That
    /// endpoint answers with plain text, unlike the whole run's,
    /// which is an archive; anything that does not read as text is
    /// dropped rather than pasted, so a prompt can never be handed
    /// an archive's bytes. Nil when neither answers, so one job
    /// still uploading never takes down the logs the others have.
    private func jobLog(_ job: RunJob, repositoryPath: String) async -> String? {
        // swiftformat:disable:next acronyms
        let jobID = String(job.databaseId)
        if let viewed = try? await gh(["run", "view", "--job", jobID, "--log-failed"], in: repositoryPath),
           viewed.standardOutput.isEmpty == false
        {
            return viewed.standardOutput.trimmingCharacters(in: .newlines)
        }
        guard let raw = try? await gh(
            ["api", "repos/{owner}/{repo}/actions/jobs/" + jobID + "/logs"],
            in: repositoryPath,
        ), Self.isText(raw.standardOutput) else {
            return nil
        }

        // The REST log has no job or step columns, so the job is
        // named once in front of its tail.
        return "[job " + (job.name ?? jobID) + "]\n"
            + raw.standardOutput.trimmingCharacters(in: .newlines)
    }
}
