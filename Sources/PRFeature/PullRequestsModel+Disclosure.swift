import AgentIDEData
import AgentIDEDomain
import Foundation

extension PullRequestsModel {
    // MARK: Internal

    /// Whether this branch has an agent session to disclose.
    var hasAIDisclosure: Bool {
        disclosure != nil
    }

    /// Names the harness and model that wrote the branch, in the
    /// template's own AI section when it has one (Homebrew's asks
    /// for exactly this, and ticking its box is what disclosing
    /// means) and at the end of the body otherwise.
    func insertAIDisclosure() {
        guard let disclosure else {
            return
        }

        if let ticked = Self.disclosing(in: prTemplate, sentence: disclosure) {
            prTemplate = ticked
            return
        }

        prBody = prBody.isEmpty ? disclosure : prBody + "\n\n" + disclosure
    }

    /// Writes the disclosure into the template's own AI section,
    /// and nowhere else: a template without one has nothing to say
    /// about it, and the body is not the place to volunteer it.
    func discloseInTemplate() {
        guard let disclosure, let ticked = Self.disclosing(in: prTemplate, sentence: disclosure) else {
            return
        }

        prTemplate = ticked
    }

    /// The sentence itself: the harness, the model and effort it was
    /// started with, and what was done with the result. Read from
    /// the session's own arguments, the only record of them, and
    /// written the way the pickers write them.
    var disclosure: String? {
        guard let worktree = branchItem?.worktree else {
            return nil
        }

        let metadata = store.load()
        guard let session = metadata.sessionsByWorktree[worktree.path],
              let agent = AgentKind.allCases.first(where: { session.hasSuffix("--" + $0.rawValue) })
        else {
            return nil
        }

        // A launch with the picker's defaults writes no flags, so
        // the defaults are what ran: the runner's first model and
        // its default effort, the same the picker showed.
        let arguments = metadata.arguments[session] ?? ""
        let choices = launchChoices(agent)
        let model = Self.model(inArguments: arguments) ?? choices.models.first
        let effort = Self.effort(inArguments: arguments) ?? choices.defaultEffort
        let named = model.map { " with " + AgentOptionName.display($0) } ?? ""
        let level = effort.map { " at " + AgentOptionName.display($0) + " effort" } ?? ""
        return agent.displayName + named + level + ", with local review and testing."
    }

    /// The model out of the arguments a session was started with;
    /// both agents name it the same way.
    static func model(inArguments arguments: String) -> String? {
        let tokens = arguments.split(separator: " ").map(String.init)
        guard let flag = tokens.firstIndex(of: "--model"), tokens.count > flag + 1 else {
            return nil
        }

        return tokens[flag + 1]
    }

    /// The effort, which Claude Code takes as a flag and Codex as a
    /// configuration override.
    static func effort(inArguments arguments: String) -> String? {
        let tokens = arguments.split(separator: " ").map(String.init)
        if let flag = tokens.firstIndex(of: "--effort"), tokens.count > flag + 1 {
            return tokens[flag + 1]
        }

        return tokens
            .first { $0.hasPrefix(Self.codexEffort) }
            .map { String($0.dropFirst(Self.codexEffort.count)) }
    }

    /// How Codex spells its effort in a session's arguments.
    private static let codexEffort = "model_reasoning_effort="

    /// The template with its AI checkbox ticked and the sentence
    /// under it, or nil when the template asks for no disclosure.
    /// The sentence goes after the guidance comment, where the
    /// template says to put it, and replaces one written before so
    /// pressing twice says it once.
    static func disclosing(in template: String, sentence: String) -> String? {
        var lines = template.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let box = lines.firstIndex(where: { $0.contains("AI/LLM") }) else {
            return nil
        }

        lines[box] = lines[box].replacing("- [ ]", with: "- [x]").replacing("* [ ]", with: "* [x]")
        let comment = lines[box...].firstIndex { $0.contains("-->") } ?? box
        let after = lines.index(after: comment)
        if let existing = lines[after...].firstIndex(where: { $0.hasSuffix("with local review and testing.") }) {
            lines[existing] = sentence
            return lines.joined(separator: "\n")
        }

        lines.insert(contentsOf: ["", sentence], at: after)
        return lines.joined(separator: "\n")
    }
}
