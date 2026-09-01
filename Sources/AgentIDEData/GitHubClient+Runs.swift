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
            var logs = [String]()
            for job in Self.failedJobs(fromJSON: jobs.standardOutput) {
                if let log = await jobLog(job, repositoryPath: repositoryPath) {
                    logs.append(log)
                }
            }
            guard logs.isEmpty == false else {
                throw error
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

        return run.jobs.filter { ($0.conclusion ?? "").uppercased() == "FAILURE" }
    }

    // MARK: Private

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
