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

    /// The reasoning efforts the agent's picker offers, in rising
    /// order.
    var efforts: [String] { get }

    /// The argv that lists the agent's current models, asked at app
    /// startup so the picker tracks the CLI rather than a hardcoded
    /// list.
    var modelListingCommand: [String] { get }

    /// The command line arguments selecting a model and effort; nil
    /// values fall back to the agent's defaults.
    func optionArguments(model: String?, effort: String?) -> String
}

extension AgentRunner {
    /// Joins a base command, verbatim extra arguments and an
    /// optional initial prompt read from a file at launch time,
    /// inside the sandbox where the shared workspace is readable.
    func command(_ base: String, _ extraArguments: String, promptFile: String? = nil) -> String {
        let trimmed = extraArguments.trimmingCharacters(in: .whitespaces)
        var joined = trimmed.isEmpty ? base : base + " " + trimmed
        if let promptFile {
            joined += " \"$(cat '" + promptFile + "')\""
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

    /// Claude Code's model listing.
    public var modelListingCommand: [String] {
        ["claude", "models"]
    }

    /// Claude Code's effort tiers.
    public var efforts: [String] {
        ["low", "medium", "high", "xhigh", "max"]
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
        let dashified = workingDirectory
            .replacing("/", with: "-")
            .replacing(".", with: "-")
        return sandboxHome + "/.claude/projects/" + dashified
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
        ["minimal", "low", "medium", "high", "xhigh"]
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
