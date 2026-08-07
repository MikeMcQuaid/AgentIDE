/// Builds and recognises the tmux session names AgentIDE owns, shaped
/// `agentide--<repository>--<branch>--<agent>`.
public enum SessionName {
    // MARK: Public

    /// The leading component of every AgentIDE session name.
    public static let prefix = "agentide"

    /// Builds the session name for a repository, branch and agent.
    public static func make(repository: String, branch: String, agent: AgentKind) -> String {
        [prefix, slug(repository), slug(branch), agent.rawValue].joined(separator: separator)
    }

    /// Whether a tmux session name was created by AgentIDE; anything
    /// else on the server is treated as foreign. The whole documented
    /// shape is validated, not just the prefix.
    public static func isAgentIDE(_ sessionName: String) -> Bool {
        let components = sessionName.split(separator: separator, omittingEmptySubsequences: false)
        guard components.count == componentCount,
              let first = components.first, first == prefix,
              components.dropFirst().dropLast().allSatisfy({ $0.isEmpty == false }),
              let agent = components.last
        else {
            return false
        }

        return AgentKind.allCases.contains { $0.rawValue == agent }
    }

    /// Lowercases a value and replaces every character outside `a-z`,
    /// `0-9` and `-`, including the `.` and `:` tmux forbids in names,
    /// then collapses and trims `-` runs so a slug never contains the
    /// `--` separator. Values with nothing usable become `unnamed`.
    public static func slug(_ value: String) -> String {
        let replaced = value.lowercased()
            .map { character in
                let allowed = ("a" ... "z").contains(character) ||
                    ("0" ... "9").contains(character) ||
                    character == "-"
                return allowed ? String(character) : "-"
            }
            .joined()
        let collapsed = replaced.split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "unnamed" : collapsed
    }

    // MARK: Private

    private static let separator = "--"
    private static let componentCount = 4
}
