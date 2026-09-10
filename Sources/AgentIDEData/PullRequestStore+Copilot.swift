import Foundation

/// When Copilot was last asked for a review of each pull request.
/// Kept in the metadata, so an ask survives a relaunch and the icon
/// stays dim until a review newer than the ask is seen. Split from
/// the store for length.
public extension PullRequestStore {
    /// Records that Copilot has just been asked.
    func rememberCopilotAsk(repositoryPath: String, number: Int) {
        store.update { $0.fetchedAt[Self.copilotKey(repositoryPath: repositoryPath, number: number)] = Date() }
    }

    /// When Copilot was last asked, nil when never from here.
    func copilotAskedAt(repositoryPath: String, number: Int) -> Date? {
        store.load().fetchedAt[Self.copilotKey(repositoryPath: repositoryPath, number: number)]
    }

    private static func copilotKey(repositoryPath: String, number: Int) -> String {
        "copilot#" + summaryKey(repositoryPath: repositoryPath, number: number)
    }
}
