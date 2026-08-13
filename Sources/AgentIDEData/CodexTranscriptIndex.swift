import AgentIDEDomain
import Foundation
import Synchronization

/// Indexes the flat Codex session tree by each session's embedded
/// working directory, so worktrees list and resume Codex
/// conversations even though nothing on disk is keyed by cwd, unlike
/// the other agent's per-directory transcripts. Heads parse once per
/// file change and cache, keeping the refresh poll cheap.
struct CodexTranscriptIndex {
    // MARK: Internal

    /// Sessions under `root` whose embedded working directory
    /// matches, newest first. The session id comes from the file's
    /// metadata line: the rollout file name is not the resume id.
    func sessions(inRoot root: String, workingDirectory: String) -> [TranscriptSession] {
        indexedEntries(root: root)
            .filter { $0.value.workingDirectory == workingDirectory }
            .map { path, entry in
                TranscriptSession(
                    id: entry.sessionID,
                    path: path,
                    agent: .codexCLI,
                    modifiedAt: entry.modifiedAt,
                    title: entry.title,
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Private

    /// One parsed session head, keyed by file path in the cache.
    private struct Entry {
        let modifiedAt: Int
        let workingDirectory: String
        let sessionID: String
        let title: String
    }

    private struct Line: Decodable {
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let type: String?
        let cwd: String?
        let id: String?
        let sessionID: String?
        let message: String?
    }

    /// Heads are enough for the metadata and the first user message;
    /// whole rollout files can be large.
    private static let headBytes = 65_536

    /// The most sessions kept indexed, newest first.
    private static let entryCap = 2_000

    private static let cache: Mutex<[String: Entry]> = .init([:])

    /// Reads the file head: the metadata line names the session and
    /// its working directory, and the first user message titles it.
    private static func parseHead(path: String, modifiedAt: Int) -> Entry? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }

        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headBytes),
              let text = String(bytes: head, encoding: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        var workingDirectory: String?
        var sessionID: String?
        var title = ""
        for raw in text.split(separator: "\n") {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)) else {
                continue
            }

            if line.type == "session_meta", let payload = line.payload {
                workingDirectory = payload.cwd
                sessionID = payload.id ?? payload.sessionID
            }
            if line.payload?.type == "user_message", let message = line.payload?.message {
                title = message
                    .split(separator: "\n")
                    .first
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                break
            }
        }
        guard let workingDirectory, let sessionID else {
            return nil
        }

        return Entry(
            modifiedAt: modifiedAt,
            workingDirectory: workingDirectory,
            sessionID: sessionID,
            title: title,
        )
    }

    /// Every session file under the root, parsed or served from the
    /// cache when unchanged.
    private func indexedEntries(root: String) -> [String: Entry] {
        let manager = FileManager.default
        var results = [String: Entry]()
        let enumerator = manager.enumerator(atPath: root)
        while let name = enumerator?.nextObject() as? String {
            guard name.hasSuffix(".jsonl") else {
                continue
            }

            let path = root + "/" + name
            let modifiedAt = Int(
                ((try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast)
                    .timeIntervalSince1970,
            )
            let cached = Self.cache.withLock { $0[path] }
            if let cached, cached.modifiedAt == modifiedAt {
                results[path] = cached
            } else if let parsed = Self.parseHead(path: path, modifiedAt: modifiedAt) {
                results[path] = parsed
            }
        }
        // The cache mirrors disk exactly and caps at the newest
        // entries, so deleted sessions drop out and it never grows
        // without bound.
        var bounded = results
        if bounded.count > Self.entryCap {
            let newest = bounded.sorted { $0.value.modifiedAt > $1.value.modifiedAt }.prefix(Self.entryCap)
            bounded = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        Self.cache.withLock { $0 = bounded }
        return bounded
    }
}
