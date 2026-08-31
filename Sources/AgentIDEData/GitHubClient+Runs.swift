import Foundation

/// Actions runs, split from the client body for length.
extension GitHubClient {
    /// The failed steps' log of one Actions run, as `gh` prints it.
    /// A run still in progress has no whole-run log to give, but
    /// each job that already failed has its own, so those answer
    /// instead of failing while the rest of the run is still
    /// deciding; only a run with nothing failed yet keeps the
    /// original refusal.
    public func failedRunLog(repositoryPath: String, runID: Int) async throws -> String {
        do {
            return try await gh(["run", "view", String(runID), "--log-failed"], in: repositoryPath).standardOutput
        } catch {
            let jobs = try await gh(["run", "view", String(runID), "--json", "jobs"], in: repositoryPath)
            let failed = Self.failedJobIDs(fromJSON: jobs.standardOutput)
            guard failed.isEmpty == false else {
                throw error
            }

            var logs = [String]()
            for jobID in failed {
                let log = try await gh(["run", "view", "--job", String(jobID), "--log-failed"], in: repositoryPath)
                logs.append(log.standardOutput.trimmingCharacters(in: .newlines))
            }
            return logs.joined(separator: "\n")
        }
    }

    /// The ids of the jobs a `--json jobs` listing says failed,
    /// separated for tests.
    static func failedJobIDs(fromJSON json: String) -> [Int] {
        guard let data = json.data(using: .utf8),
              let run = try? JSONDecoder().decode(RunJobs.self, from: data)
        else {
            return []
        }

        return run.jobs
            .filter { ($0.conclusion ?? "").uppercased() == "FAILURE" }
            .map(\.databaseId) // swiftformat:disable:this acronyms
    }

    /// The slice of `gh run view --json jobs` the fallback reads.
    private struct RunJobs: Decodable {
        let jobs: [RunJob]
    }

    /// One job of a run; beside its listing rather than nested in
    /// it, since types nest at most one level deep.
    private struct RunJob: Decodable {
        let databaseId: Int // swiftformat:disable:this acronyms
        let conclusion: String?
    }
}
