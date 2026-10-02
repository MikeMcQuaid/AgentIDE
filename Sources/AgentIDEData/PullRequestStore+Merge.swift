import AgentIDEDomain
import Foundation

public extension PullRequestStore {
    /// A merge request speeds up the usual poll without claiming it merged.
    func markMergeRequested(repositoryPath: String, branches: [String]) {
        store.update { metadata in
            for branch in branches {
                metadata.fetchedAt[Self.mergeRequestKey(repositoryPath: repositoryPath, branch: branch)] = Date()
                metadata.fetchedAt.removeValue(
                    forKey: Self.listingKey(repositoryPath: repositoryPath, scope: .branch(branch)),
                )
            }
            metadata.fetchedAt.removeValue(forKey: "queue#" + repositoryPath)
        }
    }

    /// The request's boost survives a relaunch but expires if GitHub stalls.
    func mergeRequestedRecently(repositoryPath: String, branch: String) -> Bool {
        store.load()
            .fetchedAt[Self.mergeRequestKey(repositoryPath: repositoryPath, branch: branch)]
            .map { Date().timeIntervalSince($0) < RefreshCadence.mergeRequestPatience } ?? false
    }

    internal static func mergeRequestKey(repositoryPath: String, branch: String) -> String {
        "merge-request#" + branchKey(repositoryPath: repositoryPath, branch: branch)
    }
}
