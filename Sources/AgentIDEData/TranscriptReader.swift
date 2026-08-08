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

    /// The last assistant message's text in a transcript, tolerating
    /// unknown line shapes.
    public func finalAssistantMessage(in transcript: URL) -> String? {
        guard let content = try? String(contentsOf: transcript, encoding: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
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
        let text: String?
    }
}
