import Foundation

/// What GitHub says about a branch's rules, read with read access
/// alone: the branch's own summary says whether classic protection
/// is on it and which checks that protection requires, and the
/// rules endpoint lists every ruleset rule active on it. Two things
/// come of one reading: whether a push straight to the branch would
/// be refused, and which checks a pull request into it must pass.
public extension GitHubClient {
    /// The rules on one branch.
    struct BranchRules: Equatable, Sendable {
        /// Whether classic protection is on the branch.
        public let isProtected: Bool

        /// The ruleset rule types active on the branch.
        public let ruleTypes: Set<String>

        /// The status checks a pull request into the branch must
        /// pass, by name: classic protection's contexts and every
        /// ruleset's required checks together. Empty when nothing
        /// is required, when every check counts.
        public let requiredChecks: Set<String>

        /// Whether a push straight to the branch is taken: refused
        /// by protection, and by a rule wanting a pull request or
        /// checks that only a pull request runs.
        public var takesPushes: Bool {
            isProtected == false && ruleTypes.isDisjoint(with: GitHubClient.pushRefusingRules)
        }
    }

    /// What GitHub says about a branch's rules, nil when it cannot
    /// be asked: a rules read that fails is not an empty list of
    /// rules, and read as one it would open Push on a guarded branch
    /// and count every check on a pull request that only needs some.
    func branchRules(repositoryPath: String, branch: String) async -> BranchRules? {
        let branchResult = try? await gh(
            ["api", "repos/{owner}/{repo}/branches/" + branch, "--jq", Self.branchQuery],
            in: repositoryPath,
            allowFailure: true,
        )
        guard let branchResult, branchResult.succeeded else {
            return nil
        }

        let rules = try? await gh(
            ["api", "repos/{owner}/{repo}/rules/branches/" + branch],
            in: repositoryPath,
            allowFailure: true,
        )
        guard let rules, rules.succeeded else {
            return nil
        }

        return Self.branchRules(branchJSON: branchResult.standardOutput, rulesJSON: rules.standardOutput)
    }

    /// The rules from what GitHub said; separated for tests.
    static func branchRules(branchJSON: String, rulesJSON: String) -> BranchRules {
        let branch = (try? JSONSerialization.jsonObject(with: Data(branchJSON.utf8))) as? [String: Any] ?? [:]
        let rules = (try? JSONSerialization.jsonObject(with: Data(rulesJSON.utf8))) as? [[String: Any]] ?? []
        var required = Set(branch["required"] as? [String] ?? [])
        for rule in rules where rule["type"] as? String == "required_status_checks" {
            let parameters = rule["parameters"] as? [String: Any]
            for check in parameters?["required_status_checks"] as? [[String: Any]] ?? [] {
                if let context = check["context"] as? String {
                    required.insert(context)
                }
            }
        }
        return BranchRules(
            isProtected: branch["protected"] as? Bool ?? false,
            ruleTypes: Set(rules.compactMap { $0["type"] as? String }),
            requiredChecks: required,
        )
    }

    // MARK: Internal

    /// The two facts wanted of the branch endpoint, whose answer
    /// otherwise carries the whole tip commit: whether the branch is
    /// protected and which contexts classic protection requires.
    static let branchQuery = "{protected, required: (.protection.required_status_checks.contexts // [])}"

    /// The ruleset rules under which a push straight to the branch
    /// is refused: one wants a pull request, the other wants checks
    /// that only a pull request runs.
    internal static let pushRefusingRules: Set<String> = ["pull_request", "required_status_checks"]
}
