import AgentIDEDomain
import Foundation

// MARK: - AgentRunner

/// Everything agent-specific: how to launch, resume and find the
/// transcripts of one agent CLI. All other code speaks this seam.
/// The initial prompt is read from a file at launch: pasting it
/// after launch raced the agent's terminal setup, which flushed
/// pending input and lost the prompt.
public protocol AgentRunner: Sendable {
    /// The agent this runner drives.
    var kind: AgentKind { get }

    /// The shell command that starts the agent interactively, with
    /// caller-supplied extra arguments appended verbatim and the
    /// prompt file's content as the initial message when given.
    func launchCommand(extraArguments: String, promptFile: String?) -> String

    /// The shell command that resumes a previous conversation.
    func resumeCommand(resumeID: String, extraArguments: String) -> String

    /// The directory holding transcripts for a working directory,
    /// nil when the agent has no discoverable transcripts.
    func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String?

    /// Whether `transcriptDirectory` is unique per working directory;
    /// only then can its listing be shown as one worktree's past
    /// sessions.
    var scopesTranscriptsByWorkingDirectory: Bool { get }

    /// The models offered when discovery finds nothing, most capable
    /// first.
    var models: [String] { get }

    /// The reasoning efforts the agent's picker offers, strongest
    /// first, matching the model list's most-capable-first order.
    var efforts: [String] { get }

    /// The effort a launch without a flag runs at, for saying what a
    /// session started on defaults actually used; nil when the CLI
    /// keeps that to itself.
    var defaultEffort: String? { get }

    /// The argv that lists the agent's current models, asked at app
    /// startup so the picker tracks the CLI rather than a hardcoded
    /// list.
    var modelListingCommand: [String] { get }

    /// The command line arguments selecting a model and effort; nil
    /// values fall back to the agent's defaults.
    func optionArguments(model: String?, effort: String?) -> String
}

extension AgentRunner {
    /// The version out of a `--version` answer: the CLIs wrap it in
    /// their own names and notes ("2.1.238 (Claude Code)",
    /// "codex-cli 0.149.0"), so the first token that looks like a
    /// version is taken and anything else is no answer at all.
    func parseVersion(_ output: String) -> String? {
        output
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()v")) }
            .first { token in
                // Two dotted numbers at least, so a bare word in the
                // CLI's answer is never mistaken for a version.
                let numbers = token.split(separator: ".").filter { $0.allSatisfy(\.isNumber) }
                return numbers.count == token.split(separator: ".").count && numbers.count > 1
            }
    }

    /// Joins a base command, verbatim extra arguments and an
    /// optional initial prompt read from a file at launch time,
    /// inside the sandbox where the shared workspace is readable.
    func command(_ base: String, _ extraArguments: String, promptFile: String? = nil) -> String {
        let trimmed = extraArguments.trimmingCharacters(in: .whitespaces)
        var joined = trimmed.isEmpty ? base : base + " " + trimmed
        if let promptFile {
            joined += " \"$(cat " + promptFile.shellQuoted + ")\""
        }
        return joined
    }

    /// Extracts model names from a listing's output, tolerating ANSI
    /// colour codes and prose: the first plausible token per line.
    func parseModelList(_ output: String) -> [String] {
        var names = [String]()
        for line in output.split(separator: "\n") {
            let plain = Self.strippingANSI(String(line))
            let token = plain
                .split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*•:")) }
                .first { $0.isEmpty == false }
            let lengths = 2 ... 40
            guard let token,
                  lengths.contains(token.count),
                  token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }),
                  token.contains(where: \.isLetter),
                  // Model identifiers are lowercase; prose is not.
                  token == token.lowercased(),
                  names.contains(token) == false
            else {
                continue
            }

            names.append(token)
        }
        return names
    }

    /// Removes terminal escape sequences from CLI output.
    private static func strippingANSI(_ text: String) -> String {
        var result = ""
        var inEscape = false
        for character in text {
            if character == "\u{1B}" {
                inEscape = true
            } else if inEscape {
                if character.isLetter {
                    inEscape = false
                }
            } else {
                result.append(character)
            }
        }
        return result
    }
}

// MARK: - ClaudeCodeRunner

/// Drives Anthropic's Claude Code CLI.
public struct ClaudeCodeRunner: AgentRunner {
    // MARK: Lifecycle

    /// Creates a runner.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// Claude Code.
    public var kind: AgentKind {
        .claudeCode
    }

    /// Each working directory has its own transcript directory.
    public var scopesTranscriptsByWorkingDirectory: Bool {
        true
    }

    /// The Claude model aliases offered when discovery fails.
    public var models: [String] {
        ["fable", "opus", "sonnet", "haiku"]
    }

    /// Claude Code has no listing subcommand: every argument it
    /// does not know becomes a prompt, so `claude models` started a
    /// session, answered in prose, and the words of that answer were
    /// read as model names. The curated list above stands instead.
    public var modelListingCommand: [String] {
        []
    }

    /// Claude Code's effort tiers.
    public var efforts: [String] {
        ["max", "xhigh", "high", "medium", "low"]
    }

    /// What Claude Code runs at when not told otherwise.
    public var defaultEffort: String? {
        "high"
    }

    /// How Claude Code names a working directory's transcript
    /// directory: every path separator, dot and underscore becomes a
    /// dash, so `install_method` lives under `install-method`.
    /// Leaving the underscore alone looked in a directory that never
    /// existed, and the worktree's conversations were then found
    /// only under a decoded path that did not exist either. One
    /// rule here, for the fakes to share, so a test proves this one.
    public static func projectDirectoryName(for workingDirectory: String) -> String {
        workingDirectory
            .replacing("/", with: "-")
            .replacing(".", with: "-")
            .replacing("_", with: "-")
    }

    /// `--model` and `--effort` flags.
    public func optionArguments(model: String?, effort: String?) -> String {
        var arguments = [String]()
        if let model {
            arguments += ["--model", model]
        }
        if let effort {
            arguments += ["--effort", effort]
        }
        return arguments.joined(separator: " ")
    }

    /// Starts Claude Code interactively; the sandbox's wrapper adds
    /// its permission flag.
    public func launchCommand(extraArguments: String, promptFile: String?) -> String {
        command("claude", extraArguments, promptFile: promptFile)
    }

    /// Resumes a conversation by its session id.
    public func resumeCommand(resumeID: String, extraArguments: String) -> String {
        command("claude --resume '" + resumeID + "'", extraArguments)
    }

    /// Claude Code keys transcript directories by the working
    /// directory with `/` and `.` replaced by `-`.
    public func transcriptDirectory(workingDirectory: String, sandboxHome: String) -> String? {
        sandboxHome + "/.claude/projects/" + Self.projectDirectoryName(for: workingDirectory)
    }
}

// MARK: - CodexRunner

/// Drives OpenAI's Codex CLI.
public struct CodexRunner: AgentRunner {
    // MARK: Lifecycle

    /// Creates a runner.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// Codex CLI.
    public var kind: AgentKind {
        .codexCLI
    }

    /// The flat directory mixes every working directory's sessions.
    public var scopesTranscriptsByWorkingDirectory: Bool {
        false
    }

    /// The Codex model ids offered when discovery fails; the bare
    /// nicknames are not ids `--model` accepts.
    public var models: [String] {
        ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4"]
    }

    /// Codex has no listing subcommand (a bare argument becomes an
    /// interactive prompt), but it caches the server's model list in
    /// its home; the slugs are exactly what `--model` accepts.
    public var modelListingCommand: [String] {
        [
            "grep -o '\"slug\": *\"[^\"]*\"' ~/.codex/models_cache.json"
                + " | cut -d '\"' -f4 | grep -v codex-auto-review",
        ]
    }

    /// Codex's reasoning effort levels.
    public var efforts: [String] {
        ["xhigh", "high", "medium", "low", "minimal"]
    }

    /// What Codex runs at when not told otherwise.
    public var defaultEffort: String? {
        "medium"
    }

    /// `--model` plus the reasoning effort config override.
    public func optionArguments(model: String?, effort: String?) -> String {
        var arguments = [String]()
        if let model {
            arguments += ["--model", model]
        }
        if let effort {
            arguments += ["-c", "model_reasoning_effort=" + effort]
        }
        return arguments.joined(separator: " ")
    }

    /// Starts Codex interactively.
    public func launchCommand(extraArguments: String, promptFile: String?) -> String {
        command("codex", extraArguments, promptFile: promptFile)
    }

    /// Resumes a conversation by its session id.
    public func resumeCommand(resumeID: String, extraArguments: String) -> String {
        command("codex resume '" + resumeID + "'", extraArguments)
    }

    /// Codex keeps a flat session directory per user.
    public func transcriptDirectory(workingDirectory _: String, sandboxHome: String) -> String? {
        sandboxHome + "/.codex/sessions"
    }
}
