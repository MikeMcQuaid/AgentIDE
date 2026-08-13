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

    /// A pull request title summarising a branch's commit subjects,
    /// nil when the model cannot help.
    public func pullRequestTitle(for subjects: [String]) async -> String? {
        let instructions = """
        Summarise these git commit subjects into one pull request title: \
        sentence case, imperative mood, under seventy characters, no \
        prefixes and no quotes. Answer with the title alone.
        """
        guard let raw = await respond(instructions: instructions, to: subjects.joined(separator: "\n"))
        else {
            return nil
        }

        return Self.title(fromModelAnswer: raw)
    }

    // MARK: Internal

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

    /// Normalises a model answer into a usable title, nil when
    /// nothing usable remains; models sometimes wrap answers in
    /// quotes or add commentary lines.
    static func title(fromModelAnswer raw: String) -> String? {
        let first = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let quoteMarks: Set<Character> = ["\"", "'", "`"]
        let cleaned = String(
            first.drop(while: quoteMarks.contains).reversed().drop(while: quoteMarks.contains).reversed(),
        )
        .trimmingCharacters(in: .whitespaces)
        let capped = String(cleaned.prefix(Self.titleLimit)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? nil : capped
    }

    // MARK: Private

    /// GitHub truncates long titles in most listings.
    private static let titleLimit = 72

    /// Enough prompt for a name without paying for a whole spec.
    private static let promptLimit = 500

    /// Git and the file system are happier with short branch names.
    private static let nameLimit = 40

    private let isEnabled: Bool
}
