/// How a model or effort name is written for a person: the pickers
/// show these and the pull request disclosure says them, so they
/// read the same in both.
public enum AgentOptionName {
    /// `xhigh` reads Extra High, `gpt-` ids read GPT, and a plain
    /// lowercase name is capitalised.
    public static func display(_ name: String) -> String {
        if name == "xhigh" {
            return "Extra High"
        }
        if name.hasPrefix("gpt-") {
            return "GPT " + name.dropFirst("gpt-".count)
        }

        return name.allSatisfy(\.isLowercase) ? name.capitalized : name
    }
}
