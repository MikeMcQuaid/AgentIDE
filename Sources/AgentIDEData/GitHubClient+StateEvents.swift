import Foundation

extension GitHubClient {
    /// The last event that changes the shared PR icon, not its latest
    /// comment, review, commit or check result.
    func stateChangedAt(repositoryPath: String, number: Int) async throws -> Date {
        let query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              createdAt
              timelineItems(last: 1, itemTypes: [REOPENED_EVENT, READY_FOR_REVIEW_EVENT,
                CONVERT_TO_DRAFT_EVENT, ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT]) {
                nodes {
                  ... on ReopenedEvent { createdAt }
                  ... on ReadyForReviewEvent { createdAt }
                  ... on ConvertToDraftEvent { createdAt }
                  ... on AddedToMergeQueueEvent { createdAt }
                  ... on RemovedFromMergeQueueEvent { createdAt }
                }
              }
            }
          }
        }
        """
        let result = try await gh([
            "api", "graphql", "-f", "query=" + query,
            "-F", "owner={owner}", "-F", "name={repo}", "-F", "number=" + String(number),
            "--jq", ".data.repository.pullRequest",
        ], in: repositoryPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode(StateEvents.self, from: Data(result.standardOutput.utf8))
        return events.timelineItems.nodes.last?.createdAt ?? events.createdAt
    }
}

// MARK: - StateEvents

private struct StateEvents: Decodable {
    let createdAt: Date
    let timelineItems: StateEventConnection
}

// MARK: - StateEventConnection

private struct StateEventConnection: Decodable {
    let nodes: [StateEvent]
}

// MARK: - StateEvent

private struct StateEvent: Decodable {
    let createdAt: Date
}
