import Foundation

// MARK: - MetadataStore

/// Loads and saves the metadata file. Everything else re-derives from
/// herdr, git, transcripts and GitHub, so losing this file loses only
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

    /// Changes the metadata in one step: loads, changes and saves
    /// under a lock, so two writers cannot each save a copy loaded
    /// before the other wrote. Loading, changing and saving as
    /// three steps lost whichever change was written first, which
    /// is how a branch's cached pull requests, and the session
    /// recorded for a worktree, went missing while the app was busy.
    public func update(_ change: (inout AppMetadata) -> Void) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var metadata = load()
        change(&metadata)
        save(metadata)
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

    /// Serialises every `update`. The file is one app's, so a lock
    /// in the process is all the exclusion it needs.
    private static let lock: NSLock = .init()

    private let file: String
}
