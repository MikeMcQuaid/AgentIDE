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
        Draft a pull request description from the git commit messages given. \
        Answer with the title on the first line: imperative, sentence case, under \
        51 characters, no trailing full stop. Leave the second line empty, then \
        a body summarising why the changes were made as a dash list with lines \
        under 73 characters. Answer with the title and body alone.
        """
        let input = commits.joined(separator: "\n\n").prefix(Self.commitsLimit)
        guard let raw = await respond(instructions: instructions, to: String(input)) else {
            return nil
        }

        return Self.pullRequestDescription(fromModelAnswer: raw)
    }

    // MARK: Internal

    /// Splits a model answer into title and body, nil when nothing
    /// usable came back; models sometimes wrap answers in quotes or
    /// markdown heading markers despite instructions.
    static func pullRequestDescription(fromModelAnswer raw: String) -> (title: String, body: String)? {
        let lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(
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
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
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
