import Foundation

/// Pure parsers for on-device model answers. Kept in Domain so they
/// compile without FoundationModels and so Linux and tests share the
/// same normalisation.
public enum ModelAnswerParsing {
    // MARK: Public

    /// Lays the branch out for the model: its name when given, every
    /// commit's subject first, so a tight context budget never hides
    /// later commits entirely, then each commit's whole message while
    /// the budget allows, so the why in bodies informs the draft too.
    public static func commitDigest(_ commits: [String], branch: String?, limit: Int) -> String {
        let subjects = commits.map { commit in
            commit.split(separator: "\n").first.map(String.init) ?? ""
        }
        // Parenthesised: `??` binds looser than `+`, and without
        // them a named branch lost the whole subject list.
        let head = (branch.map { "Branch: " + $0 + "\n\n" } ?? "")
            + "Subjects:\n" + subjects.joined(separator: "\n")
        var details = ""
        for (index, commit) in commits.enumerated() where commit.contains("\n") {
            let block = "\n\nCommit " + String(index + 1) + ":\n" + commit
            guard head.count + details.count + block.count <= limit else {
                break
            }

            details += block
        }
        return details.isEmpty ? head : head + "\n\nDetails:" + details
    }

    /// Splits a model answer into title and body, nil when nothing
    /// usable came back; models sometimes wrap answers in quotes or
    /// markdown heading markers despite instructions.
    public static func pullRequestDescription(fromModelAnswer raw: String) -> (title: String, body: String)? {
        let lines = strippedCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: "\n",
            omittingEmptySubsequences: false,
        )
        let title = String(lines.first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*\"'`"))
            .trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            return nil
        }

        let body = lines.dropFirst()
            .map(collapsedListMarker)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (capitalisedFirst(title), body)
    }

    /// Drops Markdown fence lines; models sometimes wrap answers in
    /// code blocks despite instructions, and a fence line carries no
    /// content of its own.
    public static func strippedCodeFences(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") == false }
            .joined(separator: "\n")
    }

    /// Uppercases only the leading character; models sometimes echo
    /// a lowercase commit subject as the title.
    public static func capitalisedFirst(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }

        return first.uppercased() + text.dropFirst()
    }

    /// Collapses repeated list markers like `- - item` to one dash;
    /// models echo commit bodies that are already dash lists and
    /// prefix another dash. Lines not starting with `- ` (including
    /// `--flags` and indented continuations) pass through untouched.
    public static func collapsedListMarker(_ line: Substring) -> String {
        let indent = line.prefix { $0 == " " }
        var rest = line.dropFirst(indent.count)
        var isListItem = false
        while rest.first == "-", rest.dropFirst().first == " " {
            isListItem = true
            rest = rest.dropFirst().drop { $0 == " " }
        }
        return isListItem ? indent + "- " + rest : String(line)
    }

    /// Normalises a model answer into a safe branch name, nil when
    /// nothing usable remains; models sometimes answer with quotes,
    /// punctuation or prose despite instructions.
    public static func branchName(fromModelAnswer raw: String) -> String? {
        var cleaned = ""
        for character in raw.lowercased() {
            cleaned.append(character.isLetter || character.isNumber ? character : " ")
        }
        let words = cleaned.split(separator: " ").map(String.init)
        var name = ""
        for word in words {
            let candidate = name.isEmpty ? word : name + "_" + word
            guard candidate.count <= nameLimit else {
                break
            }

            name = candidate
        }
        guard name.isEmpty == false, name.contains(where: \.isLetter) else {
            return nil
        }

        return name
    }

    // MARK: Private

    /// Git and the file system are happier with short branch names.
    private static let nameLimit = 40
}
