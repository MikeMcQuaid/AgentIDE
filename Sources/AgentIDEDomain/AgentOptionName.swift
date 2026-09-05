/// How a model or effort name is written for a person: the pickers
/// show these and the pull request disclosure says them, so they
/// read the same in both. What is sent to the agent is always the
/// name itself; only the reading of it changes here.
public enum AgentOptionName {
    // MARK: Public

    /// `xhigh` reads Extra High, an OpenAI id reads as its words,
    /// a Claude alias reads as the model and version it stands for,
    /// and a plain lowercase name is capitalised.
    public static func display(_ name: String) -> String {
        if name == "xhigh" {
            return "Extra High"
        }
        if let claude = claudeVersions[name] {
            return claude
        }
        if name.hasPrefix("gpt-") {
            return "GPT " + words(name.dropFirst("gpt-".count))
        }

        return name.allSatisfy(\.isLowercase) ? name.capitalized : name
    }

    // MARK: Private

    /// The version each Claude alias stands for today. Claude Code
    /// takes the alias and has no listing to ask, so the version is
    /// written here and has to be updated when the family moves; the
    /// alias is still what is sent, so an out-of-date reading here
    /// mislabels a model rather than failing to run one.
    private static let claudeVersions = [
        "fable": "Fable 5.1",
        "opus": "Opus 5",
        "sonnet": "Sonnet 5",
        "haiku": "Haiku 4.5",
    ]

    /// `5.6-sol` reads 5.6 Sol: the dashes are word breaks and each
    /// word that is not already a number is capitalised.
    private static func words(_ name: some StringProtocol) -> String {
        name.split(separator: "-")
            .lazy
            .map { part in part.allSatisfy(\.isLowercase) ? part.capitalized : String(part) }
            .joined(separator: " ")
    }
}
