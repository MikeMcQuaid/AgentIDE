import AgentIDEDomain
import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - FoundationModelClient

/// The on-device Apple foundation model, kept behind one client so
/// summarisation is reusable: branch names today, commit and pull
/// request summaries later. Every helper answers nil when the model
/// is unavailable or unhelpful, so callers always carry a fallback.
public struct FoundationModelClient: OnDeviceSummarising, Sendable {
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
        guard isEnabled else {
            return nil
        }

        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return await respondWithFoundationModel(instructions: instructions, to: input)
            }
            return nil
        #else
            return nil
        #endif
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

        return ModelAnswerParsing.branchName(fromModelAnswer: raw)
    }

    /// A commit message drafted from a diff: a subject line, a
    /// blank line and a short body. Nil when the model cannot help,
    /// so the field stays exactly as the user left it.
    public func commitMessage(fromDiff diff: String) async -> String? {
        let instructions = """
        Summarise this git diff as a commit message: a sentence-case imperative \
        subject under fifty characters, then a blank line, then one short \
        paragraph on why. No conventional-commit prefix, no quotes, no code \
        fences. Answer with the message alone.
        """
        guard let raw = await respond(instructions: instructions, to: String(diff.prefix(Self.diffLimit)))
        else {
            return nil
        }

        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// A pull request title and body drafted from the branch's
    /// commit messages, nil when the model cannot help.
    public func pullRequestDescription(
        fromCommits commits: [String],
        branch: String,
    ) async -> (title: String, body: String)? {
        let instructions = """
        Draft a pull request description from the git branch name and commits \
        given: every subject is listed first, then each commit's full message \
        while space allows. Synthesise from all of it rather than copying: never repeat \
        commit lines verbatim and never write one dash per commit. Answer with \
        the title on the first line: one imperative, sentence case summary of \
        the whole branch, under 51 characters, no trailing full stop. Leave \
        the second line empty, then summarise what changed and why across the \
        whole branch as a dash list, grouping related work, with every line \
        under 73 characters. Answer with the title and body alone.
        """
        let input = ModelAnswerParsing.commitDigest(commits, branch: branch, limit: Self.commitsLimit)
        guard let raw = await respond(instructions: instructions, to: input) else {
            return nil
        }

        return ModelAnswerParsing.pullRequestDescription(fromModelAnswer: raw)
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
        let input = ModelAnswerParsing.commitDigest(commits, branch: nil, limit: Self.commitsLimit)
            + "\n\nTemplate:\n\n" + String(template.prefix(Self.commitsLimit))
        guard let raw = await respond(instructions: instructions, to: input) else {
            return nil
        }

        let filled = ModelAnswerParsing.strippedCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return filled.isEmpty ? nil : filled
    }

    // MARK: Internal

    /// Forwards to `ModelAnswerParsing` so existing tests keep calling
    /// these names on the client.
    static func commitDigest(_ commits: [String], branch: String?, limit: Int) -> String {
        ModelAnswerParsing.commitDigest(commits, branch: branch, limit: limit)
    }

    /// Forwards to `ModelAnswerParsing`.
    static func pullRequestDescription(fromModelAnswer raw: String) -> (title: String, body: String)? {
        ModelAnswerParsing.pullRequestDescription(fromModelAnswer: raw)
    }

    /// Forwards to `ModelAnswerParsing`.
    static func strippedCodeFences(_ text: String) -> String {
        ModelAnswerParsing.strippedCodeFences(text)
    }

    /// Forwards to `ModelAnswerParsing`.
    static func capitalisedFirst(_ text: String) -> String {
        ModelAnswerParsing.capitalisedFirst(text)
    }

    /// Forwards to `ModelAnswerParsing`.
    static func collapsedListMarker(_ line: Substring) -> String {
        ModelAnswerParsing.collapsedListMarker(line)
    }

    /// Forwards to `ModelAnswerParsing`.
    static func branchName(fromModelAnswer raw: String) -> String? {
        ModelAnswerParsing.branchName(fromModelAnswer: raw)
    }

    // MARK: Private

    /// Enough of a diff to summarise without paying for a whole
    /// refactor's worth of context.
    private static let diffLimit = 8_000

    /// Enough prompt for a name without paying for a whole spec.
    private static let promptLimit = 500

    /// Enough commit text for a description within the context cap.
    private static let commitsLimit = 8_000

    private let isEnabled: Bool

    #if canImport(FoundationModels)
        @available(macOS 26, *)
        private func respondWithFoundationModel(instructions: String, to input: String) async -> String? {
            guard SystemLanguageModel.default.isAvailable else {
                return nil
            }

            let session = LanguageModelSession(instructions: instructions)
            return try? await session.respond(to: input).content
        }
    #endif
}
