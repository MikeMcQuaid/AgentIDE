/// How a model or effort name is written for a person: the pickers
/// show these and the pull request disclosure says them, so they read
/// the same in both. What is sent to the agent is always the name
/// itself; only the reading of it changes here.
public enum AgentOptionName {
    // MARK: Public

    /// `xhigh` reads Extra High, an id reads as its words, and a name
    /// the agent itself has a fuller name for reads as that. Nothing
    /// about a model's version is written here: `named` carries what
    /// the agent reported, and an alias it said nothing about is
    /// shown as it is rather than guessed at.
    public static func display(_ name: String, named: [String: String] = [:]) -> String {
        if name == "xhigh" {
            return "Extra High"
        }
        if let reported = named[name] {
            return reported
        }
        if name.hasPrefix("gpt-") {
            return "GPT " + words(name.dropFirst("gpt-".count))
        }

        return name.allSatisfy(\.isLowercase) ? name.capitalized : name
    }

    // MARK: Private

    /// `5.6-sol` reads 5.6 Sol: the dashes are word breaks and each
    /// word that is not already a number is capitalised.
    private static func words(_ name: some StringProtocol) -> String {
        name.split(separator: "-")
            .lazy
            .map { part in part.allSatisfy(\.isLowercase) ? part.capitalized : String(part) }
            .joined(separator: " ")
    }
}
