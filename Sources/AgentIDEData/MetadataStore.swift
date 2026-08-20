import Foundation

// MARK: - MetadataStore

/// Loads and saves the metadata file. Everything else re-derives from
/// tmux, git, transcripts and GitHub, so losing this file loses only
/// unread state, prompts and orphaned worktree attribution.
public struct MetadataStore: Sendable {
    // MARK: Lifecycle

    /// Creates a store at a file path.
    public init(file: String) {
        self.file = file
    }

    // MARK: Public

    /// Loads the metadata, empty when absent or unreadable.
    public func load() -> AppMetadata {
        guard let data = FileManager.default.contents(atPath: file) else {
            return AppMetadata()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppMetadata.self, from: data)) ?? AppMetadata()
    }

    /// Saves the metadata, creating parent directories as needed;
    /// the caches are capped first so the file never grows forever.
    public func save(_ metadata: AppMetadata) {
        var metadata = metadata
        metadata.enforceCacheCaps()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata) else {
            return
        }

        let url = URL(fileURLWithPath: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Private

    private let file: String
}
