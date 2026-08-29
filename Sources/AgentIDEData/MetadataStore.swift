import Foundation
import Synchronization

// MARK: - MetadataStore

/// Loads and saves the metadata file. Everything else re-derives from
/// herdr, git, transcripts and GitHub, so losing this file loses only
/// unread state, prompts and orphaned worktree attribution.
/// One decoded copy stays in memory per file: nothing but this app
/// writes the file, so every load after the first is a dictionary
/// read. Views ask models per row, and each ask was a whole-file
/// read and JSON decode on the main thread.
public struct MetadataStore: Sendable {
    // MARK: Lifecycle

    /// Creates a store at a file path.
    public init(file: String) {
        self.file = file
    }

    // MARK: Public

    /// The metadata: the in-memory copy, read from disk only the
    /// first time; empty when absent or unreadable.
    public func load() -> AppMetadata {
        if let remembered = Self.cached.withLock({ $0[file] }) {
            return remembered
        }

        let loaded = loadFromDisk()
        Self.cached.withLock { cache in
            // Another first load may have landed while this one read
            // the file; the copy already there is at least as new.
            if cache[file] == nil {
                cache[file] = loaded
            }
        }
        return loaded
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
        write(metadata)
    }

    // MARK: Private

    /// Serialises every write. The file is one app's, so a lock
    /// in the process is all the exclusion it needs.
    private static let lock: NSLock = .init()

    /// The decoded copy per file path, shared by every store on the
    /// same file.
    private static let cached: Mutex<[String: AppMetadata]> = .init([:])

    private let file: String

    private func loadFromDisk() -> AppMetadata {
        guard let data = FileManager.default.contents(atPath: file) else {
            return AppMetadata()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppMetadata.self, from: data)) ?? AppMetadata()
    }

    /// Caps, remembers and persists one metadata value, under the
    /// lock. A value equal to the copy in memory is not encoded or
    /// written at all: the poll saves its snapshot every tick, and
    /// most ticks change nothing.
    private func write(_ metadata: AppMetadata) {
        var metadata = metadata
        metadata.enforceCacheCaps()
        let unchanged = Self.cached.withLock { cache in
            if cache[file] == metadata {
                return true
            }

            cache[file] = metadata
            return false
        }
        guard unchanged == false else {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted for stable diffs; not pretty-printed, which doubled
        // the bytes encoded and written on every save.
        encoder.outputFormatting = [.sortedKeys]
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
}
