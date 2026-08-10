import AgentIDEDomain
import Foundation

/// Reads agent transcript JSONL files across the user boundary; the
/// sandbox's export ACLs make them host-readable.
public struct TranscriptReader: Sendable {
    // MARK: Lifecycle

    /// Creates a reader.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// The newest transcript file in a directory, by modification
    /// time.
    public func latestTranscript(in directory: String) -> URL? {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        let transcripts = names.filter { $0.hasSuffix(".jsonl") }.map { directory + "/" + $0 }
        return transcripts
            .max { modificationDate($0) < modificationDate($1) }
            .map { URL(fileURLWithPath: $0) }
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
    /// by the first user prompt.
    public func sessions(in directory: String, agent: AgentKind) -> [TranscriptSession] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".jsonl") }
            .map { name in
                let path = directory + "/" + name
                return TranscriptSession(
                    id: String(name.dropLast(".jsonl".count)),
                    path: path,
                    agent: agent,
                    modifiedAt: Int(modificationDate(path).timeIntervalSince1970),
                    title: title(ofTranscriptAt: path),
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
                  let parsed = try? decoder.decode(TranscriptLine.self, from: data),
                  let role = role(of: parsed.type)
            else {
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

    /// The last assistant message's text in a transcript, tolerating
    /// unknown line shapes.
    public func finalAssistantMessage(in transcript: URL) -> String? {
        guard let content = try? String(contentsOf: transcript, encoding: .utf8) else {
            return nil
        }

        let decoder = Self.makeDecoder()
        for line in content.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: data),
                  parsed.type == "assistant"
            else {
                continue
            }

            let texts = (parsed.message?.content ?? []).compactMap(\.text)
            guard texts.isEmpty == false else {
                continue
            }

            return texts.joined(separator: "\n")
        }
        return nil
    }

    // MARK: Private

    private struct TranscriptLine: Decodable {
        let type: String?
        let message: TranscriptMessage?
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

    /// Only the head of a transcript is read for its title; the first
    /// user prompt always sits there.
    private static let titleByteLimit = 65_536

    private static let titleCharacterLimit = 100

    /// The one decoder configuration: transcript JSON uses snake case
    /// keys in tool inputs.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
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
