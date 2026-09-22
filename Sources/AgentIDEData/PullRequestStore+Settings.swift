import AgentIDEDomain
import Foundation

/// What changes about as often as a repository's settings do, asked
/// once and kept: whether its default branch takes a push, which
/// checks its branches require and which labels it has. Split from
/// the store for length.
public extension PullRequestStore {
    /// Whether the repository's default branch takes a push. Asked
    /// once per repository and kept until `forgetRepositorySettings`,
    /// which the tab's refresh button is for: protection changes
    /// about as often as a repository's settings do. A GitHub that
    /// cannot be asked stores nothing, so the next visit asks again,
    /// and nothing known is a no.
    func acceptsDefaultPushes(repositoryPath: String, branch: String) async -> Bool {
        let key = "push-capability#" + repositoryPath
        if let known = store.load().directPushCapability[repositoryPath] {
            PerformanceLog.record(cacheHit: true, key)
            return known
        }

        PerformanceLog.record(cacheHit: false, key)
        guard let rules = await github.branchRules(repositoryPath: repositoryPath, branch: branch) else {
            return false
        }

        store.update { $0.directPushCapability[repositoryPath] = rules.takesPushes }
        return rules.takesPushes
    }

    /// The status checks a pull request into a branch must pass,
    /// which is what colours its rollup: asked once a day per base
    /// branch, since rules change about as often as a repository's
    /// settings do. Empty when nothing is required or nothing is
    /// known, when every check counts; a GitHub that cannot be asked
    /// keeps the last answer.
    func requiredChecks(
        repositoryPath: String,
        branch: String,
        interval: TimeInterval = capabilityInterval,
    ) async -> Set<String> {
        let key = Self.requiredChecksKey(repositoryPath: repositoryPath, branch: branch)
        let known = Set(store.load().requiredChecksCache[key] ?? [])
        guard due(key, interval: interval),
              let rules = await github.branchRules(repositoryPath: repositoryPath, branch: branch)
        else {
            return known
        }

        store.update { metadata in
            metadata.requiredChecksCache[key] = rules.requiredChecks.sorted()
            metadata.fetchedAt[key] = Date()
        }
        return rules.requiredChecks
    }

    /// The repository's labels, asked for once a day: they change
    /// about as often as its settings do, and the form asked on
    /// every visit. An answer GitHub could not give keeps the last.
    func labels(repositoryPath: String, interval: TimeInterval = capabilityInterval) async -> [String] {
        let key = "labels#" + repositoryPath
        let known = store.load().labelsCache[repositoryPath] ?? []
        guard due(key, interval: interval), let fetched = await github.labels(repositoryPath: repositoryPath) else {
            return known
        }

        store.update { metadata in
            metadata.labelsCache[repositoryPath] = fetched
            metadata.fetchedAt[key] = Date()
        }
        return fetched
    }

    /// Forgets what was read of the repository's settings, whether
    /// its default branch takes a push, which checks its branches
    /// require and which labels it has, so the next reading asks
    /// GitHub again.
    func forgetRepositorySettings(repositoryPath: String) {
        store.update { metadata in
            metadata.directPushCapability[repositoryPath] = nil
            metadata.fetchedAt = metadata.fetchedAt.filter { entry in
                entry.key != "labels#" + repositoryPath
                    && entry.key.hasPrefix(Self.requiredChecksKey(repositoryPath: repositoryPath, branch: "")) == false
            }
        }
    }

    // MARK: Internal

    /// The reader a fetch hands the client, answering from here for
    /// each base branch the rows name.
    func requiredChecksReader(repositoryPath: String) -> GitHubClient.RequiredChecksReader {
        { branch in await requiredChecks(repositoryPath: repositoryPath, branch: branch) }
    }

    internal static func requiredChecksKey(repositoryPath: String, branch: String) -> String {
        "required-checks#" + repositoryPath + "#" + branch
    }
}
