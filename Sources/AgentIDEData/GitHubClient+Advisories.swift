import AgentIDEDomain
import Foundation

// MARK: - SecurityAdvisoryDetail

/// A repository security advisory's prompt-relevant fields, as REST
/// returns them: its title and description, and what it says is
/// affected.
struct SecurityAdvisoryDetail: Decodable {
    // MARK: Lifecycle

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ghsaID = try container.decode(String.self, forKey: .ghsaID)
        title = try container.decode(String.self, forKey: .summary)
        body = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? ""
        vulnerabilities = try container.decodeIfPresent([AdvisoryVulnerability].self, forKey: .vulnerabilities) ?? []
        weaknesses = try container.decodeIfPresent([AdvisoryWeakness].self, forKey: .cwes) ?? []
    }

    // MARK: Internal

    let ghsaID: String
    let title: String
    let body: String
    let severity: String
    let vulnerabilities: [AdvisoryVulnerability]
    let weaknesses: [AdvisoryWeakness]

    /// What the advisory says beyond its description, a line each:
    /// the severity, every affected package and the weaknesses,
    /// which tell the agent where to look.
    var facts: [String] {
        var lines = [String]()
        if severity.isEmpty == false {
            lines.append("Severity: " + severity)
        }
        lines += vulnerabilities.map(\.line).filter { $0.isEmpty == false }.map { "Affects: " + $0 }
        if weaknesses.isEmpty == false {
            lines.append("Weaknesses: " + weaknesses.lazy.map { $0.cweID + " " + $0.name }.joined(separator: "; "))
        }
        return lines
    }

    // MARK: Private

    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case ghsaID = "ghsa_id"
        case summary
        case description
        case severity
        case vulnerabilities
        case cwes
    }
    // swiftlint:enable explicit_enum_raw_value
}

// MARK: - AdvisoryVulnerability

/// One affected package, version range and set of functions.
struct AdvisoryVulnerability: Decodable {
    // MARK: Lifecycle

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let named = try container.decodeIfPresent(AdvisoryPackage.self, forKey: .package)
        package = [named?.ecosystem, named?.name].compactMap(\.self).joined(separator: " ")
        range = try container.decodeIfPresent(String.self, forKey: .vulnerableVersionRange) ?? ""
        patched = try container.decodeIfPresent(String.self, forKey: .patchedVersions) ?? ""
        functions = try container.decodeIfPresent([String].self, forKey: .vulnerableFunctions) ?? []
    }

    // MARK: Internal

    let package: String
    let range: String
    let patched: String
    let functions: [String]

    /// The vulnerability as one line, empty when it names nothing.
    var line: String {
        var parts = [package, range].filter { $0.isEmpty == false }
        if patched.isEmpty == false {
            parts.append("patched in " + patched)
        }
        if functions.isEmpty == false {
            parts.append("in " + functions.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Private

    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case package
        case vulnerableVersionRange = "vulnerable_version_range"
        case patchedVersions = "patched_versions"
        case vulnerableFunctions = "vulnerable_functions"
    }
    // swiftlint:enable explicit_enum_raw_value
}

// MARK: - AdvisoryPackage

/// The package a vulnerability names, either part optional.
private struct AdvisoryPackage: Decodable {
    let ecosystem: String?
    let name: String?
}

// MARK: - AdvisoryWeakness

/// One CWE the advisory names.
struct AdvisoryWeakness: Decodable {
    // MARK: Internal

    let cweID: String
    let name: String

    // MARK: Private

    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case cweID = "cwe_id"
        case name
    }
    // swiftlint:enable explicit_enum_raw_value
}

// MARK: - Security advisories

/// Repository security advisories as prompt sources: the ones still
/// in triage or draft, which is to say still waiting on a fix.
public extension GitHubClient {
    /// The repository's advisories in triage, then in draft, newest
    /// first within each. One call per state, since the endpoint
    /// filters by one state at a time; empty when GitHub is
    /// unreachable or the account cannot read them, which takes
    /// admin or security manager access to the repository.
    func securityAdvisories(repositoryPath: String) async -> [SecurityAdvisorySummary] {
        var advisories = [SecurityAdvisorySummary]()
        for state in Self.advisoryStates {
            let result = try? await gh(
                ["api", "repos/{owner}/{repo}/security-advisories?state=\(state)&per_page=\(Self.pickerLimit)"],
                in: repositoryPath,
            )
            advisories += Self.advisories(fromJSON: result?.standardOutput ?? "")
        }
        return advisories
    }

    /// One advisory's title, description and affected packages, the
    /// seed of an agent prompt.
    internal func securityAdvisory(repositoryPath: String, ghsaID: String) async throws -> SecurityAdvisoryDetail {
        let result = try await gh(["api", "repos/{owner}/{repo}/security-advisories/" + ghsaID], in: repositoryPath)
        return try JSONDecoder().decode(SecurityAdvisoryDetail.self, from: Data(result.standardOutput.utf8))
    }

    // MARK: Internal

    /// The states the picker offers: the ones a fix is still owed.
    static let advisoryStates = ["triage", "draft"]

    /// The listing's rows as picker items; nothing from an answer
    /// that is not a listing.
    static func advisories(fromJSON json: String) -> [SecurityAdvisorySummary] {
        let rows = (try? JSONDecoder().decode([SecurityAdvisoryDetail].self, from: Data(json.utf8))) ?? []
        return rows.map { SecurityAdvisorySummary(ghsaID: $0.ghsaID, title: $0.title) }
    }

    /// The prompt for fixing an advisory. The branch, its commits and
    /// the pull request are public before the advisory is, so the
    /// closing tells the agent what none of them may say.
    internal static func advisoryPrompt(_ advisory: SecurityAdvisoryDetail, context: String) -> String {
        prompt(
            heading: "Fix security advisory " + advisory.ghsaID + ": " + advisory.title,
            body: ([advisory.body] + advisory.facts).filter { $0.isEmpty == false }.joined(separator: "\n\n"),
            context: context,
            closing: "Commit your work. The advisory is unpublished and the branch, its commits and the pull"
                + " request they open are public, so write the commit message as an ordinary improvement"
                + " would be written: what changed, in plain terms, and never why. Nothing in the commit"
                + " message, the pull request title or the pull request body may mention the advisory, its"
                + " identifier, security, a vulnerability, an exploit or a fix. Do not push.",
        )
    }
}
