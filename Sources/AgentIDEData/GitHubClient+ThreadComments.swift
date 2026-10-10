import AgentIDEDomain
import Foundation

extension GitHubClient {
    static let threadCommentPageSize = 100

    /// Large conversations need their own cursor so the last comment and all findings are retained.
    func reviewThreadComments(repositoryPath: String, threadID: String) async throws -> [ReviewThreadComment] {
        let query = "query($id: ID!, $endCursor: String) { node(id: $id) { ... on PullRequestReviewThread { "
            + "comments(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } "
            + "nodes { id author { login type: __typename } body } } } } }"
        let result = try await gh(
            ["api", "graphql", "--paginate", "--slurp", "-f", "query=" + query, "-f", "id=" + threadID],
            in: repositoryPath,
        )
        let pages = try JSONDecoder().decode([ThreadCommentsPage].self, from: Data(result.standardOutput.utf8))
        guard pages.isEmpty == false, pages.allSatisfy({ $0.data?.node != nil }) else {
            throw ThreadDecodeError(message: "the review comment pages carried incomplete data")
        }

        return pages.flatMap { $0.data?.node?.comments.nodes.compactMap { $0?.comment } ?? [] }
    }
}

// MARK: - ThreadCommentsPage

private struct ThreadCommentsPage: Decodable {
    struct Node: Decodable {
        let comments: ThreadsResponse.CommentNodes
    }

    struct DataBox: Decodable {
        let node: Node?
    }

    let data: DataBox?
}
