import Foundation
import SanductorDomain

extension GitHubClient {
    /// Complete logs for every failed job, including optional checks.
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
                throw SessionServiceError("Waiting for the job log: " + failure.name)
            }

            sections.append("CI · " + failure.name + "\n" + log)
            if isPublic {
                sections.append(failure.link)
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
