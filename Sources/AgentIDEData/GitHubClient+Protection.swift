import Foundation

/// Whether a repository's default branch takes a push at all. A
/// repository of your own usually does; a shared one guards its
/// default branch with classic protection or a ruleset that wants a
/// pull request, and a push straight to it is refused.
public extension GitHubClient {
    /// What a branch does with a push: takes it when neither classic
    /// protection nor an active rule that wants a pull request or
    /// passing checks stands in the way, refuses it otherwise, and
    /// nobody knows when GitHub cannot be asked.
    enum PushPolicy: Equatable, Sendable {
        case takesPushes
        case guarded
        case unknown
    }

    /// What GitHub says the branch does with a push.
    func pushPolicy(repositoryPath: String, branch: String) async -> PushPolicy {
        // Both reads take read access alone: the branch's own summary
        // says whether classic protection is on it, and the rules
        // endpoint lists every ruleset rule active on it.
        let branchResult = try? await gh(
            ["api", "repos/{owner}/{repo}/branches/" + branch, "--jq", ".protected"],
            in: repositoryPath,
            allowFailure: true,
        )
        guard let branchResult, branchResult.succeeded else {
            return .unknown
        }

        // A rules read that fails is not an empty list of rules: read
        // as one it would open Push on a guarded branch.
        let rules = try? await gh(
            ["api", "repos/{owner}/{repo}/rules/branches/" + branch],
            in: repositoryPath,
            allowFailure: true,
        )
        guard let rules, rules.succeeded else {
            return .unknown
        }

        let takes = Self.acceptsPushes(protectedFlag: branchResult.standardOutput, rulesJSON: rules.standardOutput)
        return takes ? .takesPushes : .guarded
    }

    /// The decision from what GitHub said; separated for tests.
    static func acceptsPushes(protectedFlag: String, rulesJSON: String) -> Bool {
        guard protectedFlag.trimmingCharacters(in: .whitespacesAndNewlines) != "true" else {
            return false
        }

        let rules = (try? JSONSerialization.jsonObject(with: Data(rulesJSON.utf8))) as? [[String: Any]] ?? []
        let types = Set(rules.compactMap { $0["type"] as? String })
        return types.isDisjoint(with: Self.pushRefusingRules)
    }

    // MARK: Internal

    /// The ruleset rules under which a push straight to the branch
    /// is refused: one wants a pull request, the other wants checks
    /// that only a pull request runs.
    internal static let pushRefusingRules: Set<String> = ["pull_request", "required_status_checks"]
}
