import Foundation
import SanductorDomain

extension GitHubClient {
    /// Job logs, never a whole run's log which could include optional failures.
    func autofixPrompt(
        _ candidate: AutofixCandidate,
        summary: PullRequestSummary,
        repositoryPath: String,
    ) async throws -> String {
        guard candidate.sources.contains(.checks) else {
            return candidate.text
        }

        var sections = [candidate.text]
        let isPublic = await repositoryIsPrivate(repositoryPath: repositoryPath) == false
        let failures = (summary.autofixChecks?.failures ?? []).filter { candidate.events.contains($0.runID) }
        for failure in failures {
            guard GitHubRemote.fullName(ofURL: failure.link) == GitHubRemote.fullName(ofURL: summary.url),
                  let url = URL(string: failure.link),
                  url.pathComponents.dropLast().last == "job",
                  let jobID = Int(url.lastPathComponent)
            else {
                continue
            }

            let job = RunJob(
                // swiftformat:disable:next acronyms
                databaseId: jobID,
                name: failure.name,
                conclusion: failure.conclusion,
                url: failure.link,
                steps: nil,
            )
            guard let log = await jobLog(job, repositoryPath: repositoryPath, complete: true) else {
                throw SessionServiceError("Waiting for the required job log: " + failure.name)
            }

            sections.append(CheckLog.format(
                log: log,
                heading: "Required CI · " + failure.name,
                byteLimit: min(CheckLog.logByteLimit, Self.autofixLogByteBudget / failures.count),
            ))
            if isPublic {
                sections.append(failure.link)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static let autofixLogByteBudget = 262_144
}
