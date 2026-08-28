import AgentIDEDomain
import Foundation
import Synchronization

/// Reads agent transcript JSONL files across the user boundary; the
/// sandbox's export ACLs make them host-readable. Titles parse once
/// per file change, the treatment `CodexTranscriptIndex` gives the
/// other agent's tree: without the cache every poll re-read the
/// head of every transcript of every worktree.
public struct TranscriptReader: Sendable {
    // MARK: Lifecycle

    /// Creates a reader.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// The newest transcript file in a directory, by modification
    /// time; each file is stat-ed once, not once per comparison.
    public func latestTranscript(in directory: String) -> URL? {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".jsonl") }
            .map { name in
                let path = directory + "/" + name
                return (path: path, modifiedAt: modificationDate(path))
            }
            .max { $0.modifiedAt < $1.modifiedAt }
            .map { URL(fileURLWithPath: $0.path) }
    }

    /// The resume id a transcript represents, its file name stem.
    public func resumeID(of transcript: URL) -> String {
        transcript.deletingPathExtension().lastPathComponent
    }

    /// When a transcript was last written, used for stall detection.
    public func modificationDate(_ path: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    /// Every session in a transcript directory, newest first, titled
    /// by the first user prompt. Titles are read from a head cache
    /// keyed by modification time, so a listing is a stat per file
    /// where it was a 64 KB read and decode per transcript; unlike
    /// the shared Codex tree, each worktree's directory is its own,
    /// so the listing itself is not worth caching against the poll.
    public func sessions(in directory: String, agent: AgentKind) -> [TranscriptSession] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".jsonl") }
            .map { name in
                let path = directory + "/" + name
                let modifiedAt = Int(modificationDate(path).timeIntervalSince1970)
                return TranscriptSession(
                    id: String(name.dropLast(".jsonl".count)),
                    path: path,
                    agent: agent,
                    modifiedAt: modifiedAt,
                    title: cachedTitle(ofTranscriptAt: path, modifiedAt: modifiedAt),
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The whole conversation as displayable log entries, tolerating
    /// unknown line shapes.
    public func entries(in transcript: URL) -> [TranscriptEntry] {
        guard let content = try? String(contentsOf: transcript, encoding: .utf8) else {
            return []
        }

        let decoder = Self.makeDecoder()
        var results = [TranscriptEntry]()
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: data)
            else {
                continue
            }

            if let payload = parsed.payload {
                appendCodexEntry(payload, to: &results)
                continue
            }
            guard let role = role(of: parsed.type) else {
                continue
            }

            for item in parsed.message?.content ?? [] {
                if let text = item.text, text.isEmpty == false {
                    results.append(TranscriptEntry(id: results.count, role: role, text: text))
                } else if item.type == "tool_use", let name = item.name {
                    let detail = item.input?.summary
                    let text = detail.map { name + ": " + $0 } ?? name
                    results.append(TranscriptEntry(id: results.count, role: .tool, text: text))
                }
            }
        }
        return results
    }

    // MARK: Internal

    /// Whether user-role text is Codex's own injected context rather
    /// than something the user typed.
    static func isInjectedCodexContext(_ text: String) -> Bool {
        text.hasPrefix("# AGENTS.md instructions")
            || text.hasPrefix("<user_instructions>")
            || text.hasPrefix("<environment_context>")
    }

    // MARK: Private

    private struct TranscriptLine: Decodable {
        let type: String?
        let message: TranscriptMessage?
        let payload: CodexPayload?
    }

    /// The Codex rollout format wraps everything in typed payloads.
    /// Current rollouts use `message` payloads with a role and a
    /// content array plus `custom_tool_call`; the flat
    /// `user_message`, `agent_message` and `function_call` shapes
    /// are older rollouts, kept readable.
    private struct CodexPayload: Decodable {
        // Absent from the JSON when a payload carries no content.
        // swiftlint:disable:next discouraged_optional_collection
        let content: [CodexContent]?
        let type: String?
        let role: String?
        let message: String?
        let name: String?
        let arguments: String?
        let input: String?
    }

    private struct CodexContent: Decodable {
        let text: String?
    }

    private struct TranscriptMessage: Decodable {
        // Absent from the JSON when a message carries no content.
        // swiftlint:disable:next discouraged_optional_collection
        let content: [TranscriptContent]?
    }

    private struct TranscriptContent: Decodable {
        let type: String?
        let name: String?
        let text: String?
        let input: ToolInput?
    }

    /// The interesting fields of a tool invocation's input, whichever
    /// the tool populates. Snake case keys like `file_path` arrive via
    /// the decoder's key strategy.
    private struct ToolInput: Decodable {
        // MARK: Internal

        let command: String?
        let filePath: String?
        let path: String?
        let pattern: String?
        let description: String?
        let prompt: String?
        let url: String?

        /// The most displayable single field, truncated.
        var summary: String? {
            let value = command ?? filePath ?? path ?? pattern ?? url ?? description ?? prompt
            return value.map { String($0.replacing("\n", with: " ").prefix(Self.summaryLimit)) }
        }

        // MARK: Private

        private static let summaryLimit = 200
    }

    /// One parsed title, keyed by file path and valid while the
    /// file's modification time stands.
    private struct CachedTitle {
        let modifiedAt: Int
        let title: String
    }

    /// Only the head of a transcript is read for its title; the first
    /// user prompt always sits there.
    private static let titleByteLimit = 65_536

    private static let titleCharacterLimit = 100

    /// The title cache mirroring `CodexTranscriptIndex`'s: keyed by
    /// path, capped at the newest.
    private static let titles: Mutex<[String: CachedTitle]> = .init([:])
    private static let titleCap = 2_000

    /// The one decoder configuration: transcript JSON uses snake case
    /// keys in tool inputs.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Maps one Codex payload onto a log entry: user and assistant
    /// messages read as prose, tool calls as tool lines. Developer
    /// messages and Codex's injected instruction preambles are
    /// machinery, not conversation, and stay hidden. The flat
    /// `user_message`, `agent_message` and `function_call` shapes
    /// are older rollouts, kept readable.
    /// Rollouts often record one utterance twice: as a flat event
    /// payload and again as a typed response item. Adjacent repeats
    /// of the same role and text collapse to one entry.
    private func appendCodexEntry(_ payload: CodexPayload, to results: inout [TranscriptEntry]) {
        let entry: TranscriptEntry? =
            switch payload.type {
            case "message":
                codexMessage(payload, id: results.count)

            case "custom_tool_call":
                codexToolLine(
                    name: payload.name,
                    detail: payload.input?.split(separator: "\n").first.map(String.init),
                    id: results.count,
                )

            case "user_message":
                codexProse(payload.message, role: .user, id: results.count)

            case "agent_message":
                codexProse(payload.message, role: .assistant, id: results.count)

            case "function_call":
                codexToolLine(name: payload.name, detail: payload.arguments, id: results.count)

            default:
                nil
            }
        if let entry, results.last.map({ $0.role == entry.role && $0.text == entry.text }) != true {
            results.append(entry)
        }
    }

    private func codexMessage(_ payload: CodexPayload, id: Int) -> TranscriptEntry? {
        let role: TranscriptEntry.Role? =
            switch payload.role {
            case "user":
                .user

            case "assistant":
                .assistant

            default:
                nil
            }
        let text = (payload.content ?? []).compactMap(\.text).joined(separator: "\n")
        guard let role, text.isEmpty == false, Self.isInjectedCodexContext(text) == false else {
            return nil
        }

        return TranscriptEntry(id: id, role: role, text: text)
    }

    private func codexProse(_ message: String?, role: TranscriptEntry.Role, id: Int) -> TranscriptEntry? {
        guard let message, message.isEmpty == false else {
            return nil
        }

        return TranscriptEntry(id: id, role: role, text: message)
    }

    private func codexToolLine(name: String?, detail: String?, id: Int) -> TranscriptEntry? {
        guard let name else {
            return nil
        }

        let suffix = detail.flatMap { $0.isEmpty ? nil : ": " + $0 } ?? ""
        return TranscriptEntry(id: id, role: .tool, text: name + suffix)
    }

    private func role(of type: String?) -> TranscriptEntry.Role? {
        switch type {
        case "user":
            .user

        case "assistant":
            .assistant

        default:
            nil
        }
    }

    /// The cached title while the file is unchanged, parsed afresh
    /// otherwise; the cache keeps the newest files when it fills.
    private func cachedTitle(ofTranscriptAt path: String, modifiedAt: Int) -> String {
        if let cached = Self.titles.withLock({ $0[path] }), cached.modifiedAt == modifiedAt {
            return cached.title
        }

        let title = title(ofTranscriptAt: path)
        Self.titles.withLock { titles in
            titles[path] = CachedTitle(modifiedAt: modifiedAt, title: title)
            if titles.count > Self.titleCap {
                let newest = titles
                    .sorted { $0.value.modifiedAt > $1.value.modifiedAt }
                    .prefix(Self.titleCap)
                titles = Dictionary(uniqueKeysWithValues: Array(newest))
            }
        }
        return title
    }

    private func title(ofTranscriptAt path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: Self.titleByteLimit),
              let head = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        defer { try? handle.close() }

        let decoder = Self.makeDecoder()
        for line in head.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: lineData),
                  parsed.type == "user",
                  let text = parsed.message?.content?.compactMap(\.text).first
            else {
                continue
            }

            let flattened = text.replacing("\n", with: " ")
            return String(flattened.prefix(Self.titleCharacterLimit))
        }
        return ""
    }
}
