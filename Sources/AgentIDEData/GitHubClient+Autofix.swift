import AgentIDEDomain
import Foundation

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
        for failure in summary.autofixChecks?.failures ?? [] where candidate.events.contains(failure.runID) {
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
            guard let log = await jobLog(job, repositoryPath: repositoryPath) else {
                throw SessionServiceError("Waiting for the required job log: " + failure.name)
            }

            sections.append(CheckLog.format(log: log, heading: "Required CI · " + failure.name, complete: true))
            if isPublic {
                sections.append(failure.link)
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
