/// The remote reviewers that can be explicitly requested.
public enum ReviewBot: String, Codable, CaseIterable, Sendable {
    // Persisted names match the existing automation source names.
    // swiftlint:disable explicit_enum_raw_value raw_value_for_camel_cased_codable_enum
    case copilot
    case codeRabbit

    // MARK: Public

    // swiftlint:enable explicit_enum_raw_value raw_value_for_camel_cased_codable_enum

    public var displayName: String {
        switch self {
        case .copilot:
            "Copilot"

        case .codeRabbit:
            "CodeRabbit"
        }
    }

    public var login: String {
        switch self {
        case .copilot:
            "copilot-pull-request-reviewer"

        case .codeRabbit:
            "coderabbitai"
        }
    }

    /// The vendored brand mark shown in review controls.
    public var iconAssetName: String {
        switch self {
        case .copilot:
            "octicon-copilot"

        case .codeRabbit:
            "reviewer-coderabbit"
        }
    }

    public func matches(_ author: String?) -> Bool {
        author == login || author == login + "[bot]"
    }
}
