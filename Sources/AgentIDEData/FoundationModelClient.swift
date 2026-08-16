import Foundation
import FoundationModels

/// The on-device Apple foundation model, kept behind one client so
/// summarisation is reusable: branch names today, commit and pull
/// request summaries later. Every helper answers nil when the model
/// is unavailable or unhelpful, so callers always carry a fallback.
public struct FoundationModelClient: Sendable {
    // MARK: Lifecycle

    /// Creates the client; availability is checked per call.
    /// `isEnabled: false` answers nil to everything, for callers and
    /// tests that need deterministic fallbacks.
    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    // MARK: Public

    /// One instruction applied to one input, nil when the on-device
    /// model is unavailable or errors.
    public func respond(instructions: String, to input: String) async -> String? {
        guard isEnabled, SystemLanguageModel.default.isAvailable else {
            return nil
        }

        let session = LanguageModelSession(instructions: instructions)
        return try? await session.respond(to: input).content
    }

    /// A short underscore-separated branch name summarising a
    /// prompt, nil when the model cannot help.
    public func branchName(for prompt: String) async -> String? {
        let instructions = """
        Summarise the user's coding task into a short git branch name: two to four \
        lowercase words joined by underscores, letters and digits only, no prefix. \
        Answer with the branch name alone.
        """
        guard let raw = await respond(instructions: instructions, to: String(prompt.prefix(Self.promptLimit)))
        else {
            return nil
        }

        return Self.branchName(fromModelAnswer: raw)
    }

    /// A pull request title and body drafted from the branch's
    /// commit messages, nil when the model cannot help.
    public func pullRequestDescription(fromCommits commits: [String]) async -> (title: String, body: String)? {
        let instructions = """
        Draft a pull request description from the git commits given: every \
        subject is listed first, then each commit's full message while space \
        allows. Synthesise from all of it rather than copying: never repeat \
        commit lines verbatim and never write one dash per commit. Answer with \
        the title on the first line: one imperative, sentence case summary of \
        the whole branch, under 51 characters, no trailing full stop. Leave \
        the second line empty, then summarise what changed and why across the \
        whole branch as a dash list, grouping related work, with every line \
        under 73 characters. Answer with the title and body alone.
        """
        let input = Self.commitDigest(commits, limit: Self.commitsLimit)
        guard let raw = await respond(instructions: instructions, to: input) else {
            return nil
        }

        return Self.pullRequestDescription(fromModelAnswer: raw)
    }

    /// The repository's pull request template completed from the
    /// branch's commit messages, nil when the model cannot help.
    public func filledTemplate(fromCommits commits: [String], template: String) async -> String? {
        let instructions = """
        Fill in the pull request template given after the commit messages. \
        Keep the template's structure, headings and checkboxes, replacing \
        placeholders and answering its sections from the commits; tick a \
        checkbox only when the commits clearly justify it. Answer with the \
        completed template alone.
        """
        let input = Self.commitDigest(commits, limit: Self.commitsLimit)
            + "\n\nTemplate:\n\n" + String(template.prefix(Self.commitsLimit))
        guard let raw = await respond(instructions: instructions, to: input) else {
            return nil
        }

        let filled = Self.strippedCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return filled.isEmpty ? nil : filled
    }

    // MARK: Internal

    /// Lays the branch's commits out for the model: every subject
    /// first, so a tight context budget never hides later commits
    /// entirely, then each commit's whole message while the budget
    /// allows, so the why in bodies informs the draft too.
    static func commitDigest(_ commits: [String], limit: Int) -> String {
        let subjects = commits.map { commit in
            commit.split(separator: "\n").first.map(String.init) ?? ""
        }
        let head = "Subjects:\n" + subjects.joined(separator: "\n")
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
    static func pullRequestDescription(fromModelAnswer raw: String) -> (title: String, body: String)? {
        let lines = Self.strippedCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines).split(
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
            .map(Self.collapsedListMarker)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (Self.capitalisedFirst(title), body)
    }

    /// Drops Markdown fence lines; models sometimes wrap answers in
    /// code blocks despite instructions, and a fence line carries no
    /// content of its own.
    static func strippedCodeFences(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") == false }
            .joined(separator: "\n")
    }

    /// Uppercases only the leading character; models sometimes echo
    /// a lowercase commit subject as the title.
    static func capitalisedFirst(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }

        return first.uppercased() + text.dropFirst()
    }

    /// Collapses repeated list markers like `- - item` to one dash;
    /// models echo commit bodies that are already dash lists and
    /// prefix another dash. Lines not starting with `- ` (including
    /// `--flags` and indented continuations) pass through untouched.
    static func collapsedListMarker(_ line: Substring) -> String {
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
    static func branchName(fromModelAnswer raw: String) -> String? {
        var cleaned = ""
        for character in raw.lowercased() {
            cleaned.append(character.isLetter || character.isNumber ? character : " ")
        }
        let words = cleaned.split(separator: " ").map(String.init)
        var name = ""
        for word in words {
            let candidate = name.isEmpty ? word : name + "_" + word
            guard candidate.count <= Self.nameLimit else {
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

    /// Enough prompt for a name without paying for a whole spec.
    private static let promptLimit = 500

    /// Enough commit text for a description within the context cap.
    private static let commitsLimit = 8_000

    /// Git and the file system are happier with short branch names.
    private static let nameLimit = 40

    private let isEnabled: Bool
}
